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

  async summary(month: string): Promise<string | null> {
    if (!MONTH_RE.test(month)) return null;
    return this.read(join("summaries", `${month}.md`));
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

  /** A markdown file inside the worklog, for showing a search hit's original. Rejects paths outside the root. */
  async file(rel: string): Promise<{ path: string; markdown: string } | null> {
    const clean = normalize(rel).replace(/^([/\\])+/, "");
    const abs = join(this.root, clean);
    if (!abs.startsWith(this.root + sep) || !clean.endsWith(".md")) return null;
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
