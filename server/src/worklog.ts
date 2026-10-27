// Reads the worklog folder (log/, projects/, summaries/) and turns it into JSON.
// The folder layout and line format are defined in kit/templates/worklog/README.md.

import { existsSync } from "node:fs";
import { appendFile, mkdir, readdir, readFile, stat, writeFile } from "node:fs/promises";
import { join, normalize, sep } from "node:path";

export type LogEntry = {
  date: string;          // "10-06" as written in the log
  projects: string[];    // slugs from [[slug]] links
  tags: string[];        // "#done" etc. without the "#"
  text: string;          // the line without date, links, tags and (src: …)
  source: string | null; // contents of "(src: …)", null when the user wrote the line
  author: "me" | "claude";
  raw: string;
};

export type ProjectSummary = {
  slug: string;
  title: string;
  status: string;
  repos: string[];
  currentState: string;
};

export const MONTH_RE = /^\d{4}-\d{2}$/;
export const SLUG_RE = /^[a-z0-9][a-z0-9._-]*$/i;

const LINE_RE = /^\s*[-*]\s+(\d{1,2}-\d{1,2})\s+(.*)$/;
const LINK_RE = /\[\[([^\]|]+)(?:\|[^\]]*)?\]\]/g;
const TAG_RE = /(^|\s)#([\p{L}\p{N}_-]+)/gu;
const SRC_RE = /\s*\(src:\s*([^)]*)\)\s*$/;

export function parseLogLine(line: string): LogEntry | null {
  const m = LINE_RE.exec(line);
  if (!m) return null;
  let rest = m[2];

  let source: string | null = null;
  const src = SRC_RE.exec(rest);
  if (src) {
    source = src[1].trim();
    rest = rest.slice(0, src.index);
  }

  const projects = [...rest.matchAll(LINK_RE)].map((x) => x[1].trim());
  const tags = [...rest.matchAll(TAG_RE)].map((x) => x[2]);
  const text = rest
    .replace(LINK_RE, "")
    .replace(TAG_RE, "$1")
    .replace(/\s+/g, " ")
    .trim();

  return {
    date: m[1],
    projects,
    tags,
    text,
    source,
    author: source === null ? "me" : "claude",
    raw: line.trim(),
  };
}

export function parseLog(markdown: string): LogEntry[] {
  return markdown
    .split(/\r?\n/)
    .map(parseLogLine)
    .filter((e): e is LogEntry => e !== null);
}

/** Minimal YAML front matter reader: `key: value` and `key: [a, b]` only. */
export function parseFrontMatter(markdown: string): { meta: Record<string, string | string[]>; body: string } {
  const m = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(markdown);
  if (!m) return { meta: {}, body: markdown };
  const meta: Record<string, string | string[]> = {};
  for (const line of m[1].split(/\r?\n/)) {
    const kv = /^([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*(#.*)?$/.exec(line);
    if (!kv) continue;
    const value = kv[2];
    const list = /^\[(.*)\]$/.exec(value);
    meta[kv[1]] = list
      ? list[1].split(",").map((s) => s.trim()).filter(Boolean)
      : value;
  }
  return { meta, body: markdown.slice(m[0].length) };
}

/** Text under a "## <heading>" until the next "## ". */
export function section(body: string, heading: string): string {
  const lines = body.split(/\r?\n/);
  const start = lines.findIndex((l) => l.trim() === `## ${heading}`);
  if (start < 0) return "";
  const out: string[] = [];
  for (const l of lines.slice(start + 1)) {
    if (/^##\s/.test(l)) break;
    out.push(l);
  }
  return out.join("\n").trim();
}

export function parseProject(slug: string, markdown: string): ProjectSummary {
  const { meta, body } = parseFrontMatter(markdown);
  const title = /^#\s+(.+)$/m.exec(body)?.[1].trim() ?? slug;
  const repos = Array.isArray(meta.repos) ? meta.repos : [];
  const status = typeof meta.status === "string" ? meta.status : "";
  return { slug, title, status, repos, currentState: section(body, "현재 상태") };
}

export class Worklog {
  readonly root: string;
  constructor(root: string) {
    this.root = root;
  }

  private async listMd(dir: string): Promise<string[]> {
    try {
      const names = await readdir(join(this.root, dir));
      return names.filter((n) => n.endsWith(".md") && !n.startsWith("_") && !n.startsWith("."));
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") return [];
      throw err;
    }
  }

  async months(dir: "log" | "summaries"): Promise<string[]> {
    return (await this.listMd(dir))
      .map((n) => n.slice(0, -3))
      .filter((n) => MONTH_RE.test(n))
      .sort()
      .reverse();
  }

  async log(month: string): Promise<LogEntry[] | null> {
    if (!MONTH_RE.test(month)) return null;
    const text = await this.read(join("log", `${month}.md`));
    return text === null ? null : parseLog(text);
  }

  /** The month's summary without the front matter a report run puts on it (kind, createdAt, agent …). */
  async summary(month: string): Promise<string | null> {
    if (!MONTH_RE.test(month)) return null;
    const md = await this.read(join("summaries", `${month}.md`));
    return md === null ? null : parseFrontMatter(md).body;
  }

  async projects(): Promise<ProjectSummary[]> {
    const out: ProjectSummary[] = [];
    for (const name of await this.listMd("projects")) {
      const slug = name.slice(0, -3);
      const text = await this.read(join("projects", name));
      if (text !== null) out.push(parseProject(slug, text));
    }
    return out.sort((a, b) => a.slug.localeCompare(b.slug));
  }

  async project(slug: string): Promise<(ProjectSummary & { markdown: string }) | null> {
    if (!SLUG_RE.test(slug) || slug.includes("..")) return null;
    const text = await this.read(join("projects", `${slug}.md`));
    if (text === null) return null;
    return { ...parseProject(slug, text), markdown: parseFrontMatter(text).body };
  }

  async appendLog(e: NewLogLine): Promise<{ month: string; line: string }> {
    const line = formatLogLine(e);
    const d = e.date ?? new Date();
    const month = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
    const file = join(this.root, "log", `${month}.md`);
    await mkdir(join(this.root, "log"), { recursive: true });
    if (!existsSync(file)) await writeFile(file, `# ${month} 로그\n\n`);
    const cur = await readFile(file, "utf8");
    await appendFile(file, (cur.endsWith("\n") ? "" : "\n") + line + "\n");
    return { month, line };
  }

  /**
   * Rewrites one line of log/<month>.md. The line is identified by its exact current text (`raw`),
   * so a stale client cannot overwrite an edit it has not seen. Fields left out keep their values;
   * the `(src: …)` marker of a line the digest wrote is preserved.
   */
  async updateLog(month: string, raw: string, patch: { text?: string; tags?: string[]; projects?: string[]; date?: string }): Promise<{ line: string } | null> {
    if (!MONTH_RE.test(month)) return null;
    const file = join(this.root, "log", `${month}.md`);
    const md = await this.read(join("log", `${month}.md`));
    if (md === null) return null;
    const lines = md.split(/\r?\n/);
    const i = lines.findIndex((l) => l.trim() === raw.trim());
    if (i < 0) return null;
    const cur = parseLogLine(lines[i])!;
    const date = patch.date ?? cur.date;
    if (!/^\d{1,2}-\d{1,2}$/.test(date)) throw new Error(`날짜 형식이 올바르지 않습니다: ${date} (예: 10-06)`);
    const [mm, dd] = date.split("-").map(Number);
    const text = (patch.text ?? cur.text).trim() + (cur.source ? ` (src: ${cur.source})` : "");
    const line = formatLogLine({ text, tags: patch.tags ?? cur.tags, projects: patch.projects ?? cur.projects, date: new Date(Number(month.slice(0, 4)), mm - 1, dd, 12) });
    lines[i] = line;
    await writeFile(file, lines.join("\n"));
    return { line };
  }

  /** Removes one line of log/<month>.md, identified by its exact text. */
  async deleteLog(month: string, raw: string): Promise<boolean> {
    if (!MONTH_RE.test(month)) return false;
    const file = join(this.root, "log", `${month}.md`);
    const md = await this.read(join("log", `${month}.md`));
    if (md === null) return false;
    const lines = md.split(/\r?\n/);
    const i = lines.findIndex((l) => l.trim() === raw.trim());
    if (i < 0) return false;
    lines.splice(i, 1);
    await writeFile(file, lines.join("\n"));
    return true;
  }

  async inbox(): Promise<Record<"transcripts" | "sessions" | "audio", InboxFile[]>> {
    return {
      transcripts: await listDir(join(this.root, "inbox", "transcripts")),
      sessions: await listDir(join(this.root, "inbox", "claude-sessions")),
      audio: await listDir(join(this.root, "inbox", "audio")),
    };
  }

  async saveTranscript(name: string, text: string, date = new Date()): Promise<string> {
    if (!text.trim()) throw new Error("전사본 내용이 비어 있습니다.");
    const dir = join(this.root, "inbox", "transcripts");
    await mkdir(dir, { recursive: true });
    const file = freePath(dir, safeStem(name, date), ".txt");
    await writeFile(file, text.endsWith("\n") ? text : text + "\n");
    return file;
  }

  /**
   * What the daily collect and the inbox produced, newest first: every `sources/<name>/<date>.md`
   * day file plus transcripts and session notes in inbox/ and processed/. This is the "원본" layer
   * of the memory tab — the material the log lines and reports were written from.
   */
  async origins(limit = 400): Promise<OriginFile[]> {
    const out: OriginFile[] = [];
    const add = async (dir: string, source: string, kind: OriginFile["kind"]) => {
      let names: string[];
      try {
        names = await readdir(join(this.root, dir));
      } catch {
        return;
      }
      for (const n of names) {
        if (n.startsWith(".") || n.startsWith("_")) continue;
        const date = /(\d{4}-\d{2}-\d{2})/.exec(n)?.[1];
        if (!date) continue;
        try {
          const st = await stat(join(this.root, dir, n));
          if (!st.isFile()) continue;
          out.push({ path: `${dir}/${n}`, source, kind, date, name: n, bytes: st.size });
        } catch {}
      }
    };
    let sourceDirs: string[] = [];
    try {
      sourceDirs = (await readdir(join(this.root, "sources"))).filter((n) => !n.startsWith("."));
    } catch {}
    for (const s of sourceDirs) await add(`sources/${s}`, s, "source");
    await add("inbox/transcripts", "transcripts", "inbox");
    await add("processed/transcripts", "transcripts", "processed");
    await add("inbox/claude-sessions", "session-notes", "inbox");
    await add("processed/claude-sessions", "session-notes", "processed");
    out.sort((a, b) => (a.date === b.date ? a.path.localeCompare(b.path) : a.date < b.date ? 1 : -1));
    return out.slice(0, limit);
  }

  /**
   * The file(s) behind a log line's `(src: …)` marker, so the memory tab can jump from a line to
   * the material it was written from. Formats (kit/templates/worklog/README.md):
   * "git <repo> <hash7>" · "<source> YYYY-MM-DD" (claude-code, agent-sessions, shell, 커넥터 이름) ·
   * "YYYY-MM-DD_제목" (transcript or session note). Several may be joined with ", ".
   */
  async resolveSource(src: string): Promise<string[]> {
    const found: string[] = [];
    const exists = async (rel: string) => {
      try {
        return (await stat(join(this.root, rel))).isFile();
      } catch {
        return false;
      }
    };
    for (const part of src.split(/\s*[,;]\s*/).map((p) => p.trim()).filter(Boolean)) {
      let m: RegExpExecArray | null;
      if ((m = /^git\s+\S+\s+([0-9a-f]{7,40})$/i.exec(part))) {
        // the commit's day file: search the git day files, newest first
        const hash = m[1].toLowerCase();
        for (const n of (await this.listMd("sources/git")).sort().reverse()) {
          const text = await this.read(`sources/git/${n}`);
          if (text && text.toLowerCase().includes(hash)) {
            found.push(`sources/git/${n}`);
            break;
          }
        }
        continue;
      }
      if ((m = /^([\w-]+)\s+(\d{4}-\d{2}-\d{2})$/.exec(part))) {
        const name = { shell: "shell-history", "claude-code": "claude-code" }[m[1]] ?? m[1];
        // agent-sessions replaced claude-code (2026-10-27): a marker of either name may point at a day file of the other
        const twin = name === "claude-code" ? "agent-sessions" : name === "agent-sessions" ? "claude-code" : null;
        const candidates = [`sources/${name}/${m[2]}.md`, ...(twin ? [`sources/${twin}/${m[2]}.md`] : [])];
        for (const c of candidates) if (await exists(c)) {
          found.push(c);
          break;
        }
        continue;
      }
      if (/^\d{4}-\d{2}-\d{2}[_ ]/.test(part) || /^\d{4}-\d{2}-\d{2}$/.test(part)) {
        const base = part.replace(/\.(txt|md)$/, "");
        for (const c of [
          `processed/transcripts/${base}.txt`, `processed/transcripts/${base}.md`, `inbox/transcripts/${base}.txt`, `inbox/transcripts/${base}.md`,
          `processed/claude-sessions/${base}.md`, `inbox/claude-sessions/${base}.md`,
        ]) if (await exists(c)) {
          found.push(c);
          break;
        }
      }
    }
    return found;
  }

  /** A text file inside the worklog (.md or .txt), for showing a search hit's or a log line's original. Rejects paths outside the root. */
  async file(rel: string): Promise<{ path: string; markdown: string } | null> {
    const clean = normalize(rel).replace(/^([/\\])+/, "");
    const abs = join(this.root, clean);
    if (!abs.startsWith(this.root + sep) || !/\.(md|txt)$/.test(clean)) return null;
    const markdown = await this.read(clean);
    return markdown === null ? null : { path: clean, markdown };
  }

  private async read(rel: string): Promise<string | null> {
    try {
      return await readFile(join(this.root, rel), "utf8");
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw err;
    }
  }
}

// ── real-time input ──────────────────────────────────────────────────────────

export type NewLogLine = { text: string; tags?: string[]; projects?: string[]; date?: Date };

/** One collected/ingested file, as the memory tab lists it. */
export type OriginFile = {
  path: string;
  /** Source name: git, agent-sessions, shell-history, a connector name, "transcripts", "session-notes". */
  source: string;
  kind: "source" | "inbox" | "processed";
  date: string;
  name: string;
  bytes: number;
};

const TAG_OK = /^[\p{L}\p{N}_-]{1,30}$/u;

export function formatLogLine(e: NewLogLine): string {
  const text = e.text.replace(/\s+/g, " ").trim();
  if (!text) throw new Error("내용이 비어 있습니다.");
  if (text.length > 500) throw new Error("한 줄은 500자 이내로 써 주세요.");
  const d = e.date ?? new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  const projects = (e.projects ?? []).map((x) => x.trim()).filter(Boolean);
  const tags = (e.tags ?? []).map((x) => x.replace(/^#/, "").trim()).filter(Boolean);
  for (const s of projects) if (!SLUG_RE.test(s) || s.includes("..")) throw new Error(`프로젝트 이름이 올바르지 않습니다: ${s}`);
  for (const t of tags) if (!TAG_OK.test(t)) throw new Error(`태그가 올바르지 않습니다: ${t}`);
  return ["-", `${p(d.getMonth() + 1)}-${p(d.getDate())}`, ...projects.map((x) => `[[${x}]]`), ...tags.map((t) => `#${t}`), text].join(" ");
}

export type InboxFile = { name: string; size: number; modified: string };

export async function listDir(dir: string): Promise<InboxFile[]> {
  try {
    const names = (await readdir(dir)).filter((n) => !n.startsWith("."));
    const out: InboxFile[] = [];
    for (const name of names) {
      const st = await stat(join(dir, name));
      if (st.isFile()) out.push({ name, size: st.size, modified: st.mtime.toISOString() });
    }
    return out.sort((a, b) => b.modified.localeCompare(a.modified));
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw err;
  }
}

/** "주간 회의" → "2026-10-23_주간_회의" (keeps an existing date prefix). */
export function safeStem(name: string, date = new Date()): string {
  const stem = name.replace(/\.[A-Za-z0-9]{1,5}$/, "").replace(/[^\p{L}\p{N}._-]+/gu, "_").replace(/^[._]+/, "").slice(0, 80) || "memo";
  if (/^\d{4}-\d{2}-\d{2}/.test(stem)) return stem;
  const p = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${p(date.getMonth() + 1)}-${p(date.getDate())}_${stem}`;
}

export function freePath(dir: string, stem: string, ext: string): string {
  let p = join(dir, stem + ext);
  for (let i = 2; existsSync(p); i++) p = join(dir, `${stem}_${i}${ext}`);
  return p;
}
