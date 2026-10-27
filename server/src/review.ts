// Review before apply: a digest run (any agent) works on the real worklog, then its changes are lifted
// out into a *proposal* and the files are put back. The user picks what to keep in the app, and only
// that is written. Works for every agent because it looks at files, not at what the agent said.
//
//   proposal  $ZAEVIS_HOME/digest/proposals/<id>.json

import { existsSync } from "node:fs";
import { mkdir, readdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import { stateDir } from "./config.ts";
import { parseLogLine, type LogEntry } from "./worklog.ts";

/** Files the weekly procedure may touch, relative to the worklog root. */
const TRACKED_DIRS = ["log", "projects", "summaries"];
const INBOX_DIRS = ["inbox/transcripts", "inbox/claude-sessions"];

export type Snapshot = {
  files: Record<string, string>; // rel path → content (tracked dirs + .state.md)
  inbox: string[]; // rel paths of inbox files
};

export type ProposedLine = { month: string; line: string; entry: LogEntry };
export type ProposedProject = { slug: string; before: string | null; after: string };
export type ProposedFile = { path: string; before: string | null; after: string };

export type Proposal = {
  id: string;
  createdAt: string;
  agent: string;
  report: string;
  status: "pending" | "applied" | "dismissed";
  logLines: ProposedLine[];
  /** Log lines the agent removed (it should not; shown so nothing is lost silently). */
  removedLines: ProposedLine[];
  projects: ProposedProject[];
  summaries: ProposedFile[];
  /** inbox files the agent moved to processed/ (relative paths, before → after). */
  processed: Array<{ from: string; to: string }>;
  stateAfter: string | null;
  appliedAt?: string;
};

async function listFiles(root: string, rel: string): Promise<string[]> {
  try {
    const names = await readdir(join(root, rel));
    return names.filter((n) => !n.startsWith(".")).sort().map((n) => `${rel}/${n}`);
  } catch {
    return [];
  }
}

export async function takeSnapshot(root: string): Promise<Snapshot> {
  const files: Record<string, string> = {};
  for (const dir of TRACKED_DIRS) {
    for (const rel of await listFiles(root, dir)) {
      if (rel.endsWith(".md")) files[rel] = await readFile(join(root, rel), "utf8");
    }
  }
  if (existsSync(join(root, ".state.md"))) files[".state.md"] = await readFile(join(root, ".state.md"), "utf8");
  const inbox: string[] = [];
  for (const dir of INBOX_DIRS) inbox.push(...(await listFiles(root, dir)));
  return { files, inbox };
}

/** Multiset difference of log lines: lines in `after` that `before` does not have, and vice versa. */
function lineDiff(before: string, after: string): { added: string[]; removed: string[] } {
  const count = new Map<string, number>();
  for (const l of before.split(/\r?\n/)) {
    const t = l.trim();
    if (t) count.set(t, (count.get(t) ?? 0) + 1);
  }
  const added: string[] = [];
  for (const l of after.split(/\r?\n/)) {
    const t = l.trim();
    if (!t) continue;
    const c = count.get(t) ?? 0;
    if (c > 0) count.set(t, c - 1);
    else added.push(t);
  }
  const removed = [...count.entries()].flatMap(([l, c]) => Array(c).fill(l) as string[]);
  return { added, removed };
}

/** What changed since the snapshot, as a proposal (without id/agent/report — the runner fills those). */
export async function diffSnapshot(root: string, before: Snapshot): Promise<Omit<Proposal, "id" | "createdAt" | "agent" | "report" | "status">> {
  const after = await takeSnapshot(root);
  const logLines: ProposedLine[] = [];
  const removedLines: ProposedLine[] = [];
  const projects: ProposedProject[] = [];
  const summaries: ProposedFile[] = [];
  const paths = new Set([...Object.keys(before.files), ...Object.keys(after.files)]);
  for (const rel of paths) {
    const b = before.files[rel];
    const a = after.files[rel];
    if (a === undefined || a === b) continue; // deleted files are left alone (not proposed)
    if (rel.startsWith("log/")) {
      const month = basename(rel, ".md");
      const d = lineDiff(b ?? "", a);
      for (const line of d.added) {
        const entry = parseLogLine(line);
        if (entry) logLines.push({ month, line, entry });
      }
      for (const line of d.removed) {
        const entry = parseLogLine(line);
        if (entry) removedLines.push({ month, line, entry });
      }
    } else if (rel.startsWith("projects/")) {
      const slug = basename(rel, ".md");
      if (!slug.startsWith("_")) projects.push({ slug, before: b ?? null, after: a });
    } else if (rel.startsWith("summaries/")) {
      summaries.push({ path: rel, before: b ?? null, after: a });
    }
  }
  const processed: Array<{ from: string; to: string }> = [];
  const nowInbox = new Set(after.inbox);
  for (const from of before.inbox) {
    if (nowInbox.has(from)) continue;
    const to = from.replace(/^inbox\//, "processed/");
    if (existsSync(join(root, to))) processed.push({ from, to });
  }
  const stateAfter = after.files[".state.md"] !== before.files[".state.md"] ? (after.files[".state.md"] ?? null) : null;
  return { logLines, removedLines, projects, summaries, processed, stateAfter };
}

/** Puts every tracked file and inbox move back the way the snapshot had it. */
export async function restoreSnapshot(root: string, before: Snapshot): Promise<void> {
  const after = await takeSnapshot(root);
  for (const rel of Object.keys(after.files)) {
    if (!(rel in before.files)) await rm(join(root, rel), { force: true }); // created by the run
  }
  for (const [rel, content] of Object.entries(before.files)) {
    if (after.files[rel] !== content) {
      await mkdir(dirname(join(root, rel)), { recursive: true });
      await writeFile(join(root, rel), content);
    }
  }
  const nowInbox = new Set(after.inbox);
  for (const from of before.inbox) {
    if (nowInbox.has(from)) continue;
    const to = join(root, from.replace(/^inbox\//, "processed/"));
    if (existsSync(to)) {
      await mkdir(dirname(join(root, from)), { recursive: true });
      await rename(to, join(root, from));
    }
  }
}

export const isEmptyProposal = (p: Pick<Proposal, "logLines" | "projects" | "summaries" | "processed">): boolean =>
  !p.logLines.length && !p.projects.length && !p.summaries.length && !p.processed.length;

export type Selection = {
  lines?: number[]; // indexes into logLines; undefined = all
  projects?: string[]; // slugs; undefined = all
  summaries?: boolean; // default true
  processed?: boolean; // default true
};

/** Writes the chosen parts of a proposal into the worklog. */
export async function applyProposal(root: string, p: Proposal, sel: Selection = {}): Promise<{ lines: number; projects: string[]; summaries: number; processed: number }> {
  const lineIdx = sel.lines ?? p.logLines.map((_, i) => i);
  const byMonth = new Map<string, string[]>();
  for (const i of lineIdx) {
    const l = p.logLines[i];
    if (!l) continue;
    byMonth.set(l.month, [...(byMonth.get(l.month) ?? []), l.line]);
  }
  let lines = 0;
  for (const [month, added] of byMonth) {
    const file = join(root, "log", `${month}.md`);
    await mkdir(dirname(file), { recursive: true });
    let cur = existsSync(file) ? await readFile(file, "utf8") : `# ${month} 로그\n\n`;
    if (!cur.endsWith("\n")) cur += "\n";
    await writeFile(file, cur + added.join("\n") + "\n");
    lines += added.length;
  }
  const slugs = sel.projects ?? p.projects.map((x) => x.slug);
  const written: string[] = [];
  for (const pr of p.projects) {
    if (!slugs.includes(pr.slug)) continue;
    const file = join(root, "projects", `${pr.slug}.md`);
    await mkdir(dirname(file), { recursive: true });
    await writeFile(file, pr.after);
    written.push(pr.slug);
  }
  let summaries = 0;
  if (sel.summaries !== false) {
    for (const s of p.summaries) {
      await mkdir(dirname(join(root, s.path)), { recursive: true });
      await writeFile(join(root, s.path), s.after);
      summaries++;
    }
  }
  let processed = 0;
  if (sel.processed !== false) {
    for (const m of p.processed) {
      const from = join(root, m.from);
      if (!existsSync(from)) continue;
      await mkdir(dirname(join(root, m.to)), { recursive: true });
      await rename(from, join(root, m.to));
      processed++;
    }
  }
  if (p.stateAfter !== null) await writeFile(join(root, ".state.md"), p.stateAfter);
  return { lines, projects: written, summaries, processed };
}

// ── storage ────────────────────────────────────────────────────────────────────

const dir = () => join(stateDir(), "digest", "proposals");

export async function saveProposal(p: Proposal): Promise<void> {
  await mkdir(dir(), { recursive: true });
  await writeFile(join(dir(), `${p.id}.json`), JSON.stringify(p, null, 2) + "\n");
}

export async function loadProposal(id: string): Promise<Proposal | null> {
  if (!/^[\w-]+$/.test(id)) return null;
  try {
    return JSON.parse(await readFile(join(dir(), `${id}.json`), "utf8")) as Proposal;
  } catch {
    return null;
  }
}

export type ProposalSummary = Pick<Proposal, "id" | "createdAt" | "agent" | "status" | "appliedAt"> & { lines: number; projects: number; summaries: number; processed: number };

export async function listProposals(): Promise<ProposalSummary[]> {
  let names: string[];
  try {
    names = (await readdir(dir())).filter((n) => n.endsWith(".json")).sort().reverse();
  } catch {
    return [];
  }
  const out: ProposalSummary[] = [];
  for (const n of names.slice(0, 30)) {
    const p = await loadProposal(basename(n, ".json"));
    if (p) out.push({ id: p.id, createdAt: p.createdAt, agent: p.agent, status: p.status, appliedAt: p.appliedAt, lines: p.logLines.length, projects: p.projects.length, summaries: p.summaries.length, processed: p.processed.length });
  }
  return out;
}

export const newProposalId = (d = new Date()): string => d.toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "").replace("T", "-");
