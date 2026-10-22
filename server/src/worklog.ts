// Reads the worklog folder (log/, projects/, summaries/) and turns it into JSON.
// The folder layout and line format are defined in kit/templates/worklog/README.md.

import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

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

  private async read(rel: string): Promise<string | null> {
    try {
      return await readFile(join(this.root, rel), "utf8");
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw err;
    }
  }
}
