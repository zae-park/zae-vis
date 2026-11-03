// The worklog's .md/.txt files as the chat sees them: a catalog, labels by folder, and the candidates a chat line may
// be about. Which one a line means is decided by Jev or the answering agent (ask.ts), not by word lists here.
// Nothing here writes.

import { readdir, stat } from "node:fs/promises";
import { join } from "node:path";

export type CatalogFile = { path: string; name: string; bytes: number; mtime: number };
export type FoundFile = { path: string; name: string; bytes: number; date: string | null; kind: string };

const SKIP_DIRS = new Set(["node_modules", "audio"]);

/** Every .md/.txt under the worklog (dot and underscore names, inbox/audio left out), up to [maxDepth] folders deep. */
export async function listWorklogFiles(root: string, maxDepth = 4): Promise<CatalogFile[]> {
  const out: CatalogFile[] = [];
  const walk = async (rel: string, depth: number) => {
    let names: string[];
    try {
      names = await readdir(join(root, rel));
    } catch {
      return;
    }
    for (const n of names) {
      if (n.startsWith(".") || n.startsWith("_")) continue;
      const childRel = rel ? `${rel}/${n}` : n;
      let st;
      try {
        st = await stat(join(root, childRel));
      } catch {
        continue;
      }
      if (st.isDirectory()) {
        if (depth < maxDepth && !SKIP_DIRS.has(n)) await walk(childRel, depth + 1);
      } else if (st.isFile() && /\.(md|txt)$/i.test(n)) {
        out.push({ path: childRel, name: n, bytes: st.size, mtime: st.mtimeMs });
      }
    }
  };
  await walk("", 0);
  return out;
}

/** What each folder holds, for the labels the chat and the router show. */
const FOLDERS: Array<[string, string]> = [
  ["inbox/transcripts", "전사본"],
  ["processed/transcripts", "전사본"],
  ["sources/transcripts", "전사본 목록"],
  ["sources/git", "git 커밋"],
  ["sources/shell-history", "셸 이력"],
  ["sources/agent-sessions", "에이전트 세션"],
  ["sources/claude-code", "에이전트 세션"],
  ["inbox/claude-sessions", "에이전트 세션"],
  ["processed/claude-sessions", "에이전트 세션"],
  ["reports/daily", "일간 리포트"],
  ["reports/weekly", "주간 리포트"],
  ["summaries", "월간 정리"],
  ["log", "한 줄 기록"],
  ["projects", "프로젝트"],
];

export function kindOf(path: string): string {
  for (const [dir, label] of FOLDERS) if (path.startsWith(`${dir}/`)) return label;
  const m = /^sources\/([^/]+)\//.exec(path);
  return m ? m[1] : path.split("/")[0] ?? "";
}

export function dateOf(name: string): string | null {
  return /(\d{4}-\d{2}-\d{2})/.exec(name)?.[1] ?? /(\d{4}-W?\d{2})(?!-\d)/.exec(name)?.[1] ?? null;
}

export const foundFile = (f: CatalogFile): FoundFile => ({ path: f.path, name: f.name, bytes: f.bytes, date: dateOf(f.name), kind: kindOf(f.path) });

/** A file the router or the answering agent may pick, with why it is offered ("앞 화면 [2]"). */
export type Candidate = FoundFile & { note?: string };

/**
 * The files a chat line can be about: [pinned] ones first (what the chat just showed, the top search hits), then the
 * newest few of every folder, newest first. Folder listings that only name other files (sources/transcripts) are left out.
 */
export function candidateFiles(catalog: CatalogFile[], opts: { pinned?: Array<{ path: string; note?: string }>; perFolder?: number; max?: number } = {}): Candidate[] {
  const byPath = new Map(catalog.map((f) => [f.path, f]));
  const out: Candidate[] = [];
  const seen = new Set<string>();
  for (const p of opts.pinned ?? []) {
    const f = byPath.get(p.path);
    if (!f || seen.has(f.path)) continue;
    seen.add(f.path);
    out.push({ ...foundFile(f), ...(p.note ? { note: p.note } : {}) });
  }
  const when = (f: CatalogFile) => dateOf(f.name) ?? new Date(f.mtime).toISOString().slice(0, 10);
  const folders = new Map<string, CatalogFile[]>();
  for (const f of catalog) {
    if (seen.has(f.path) || f.path.startsWith("sources/transcripts/")) continue;
    const dir = f.path.includes("/") ? f.path.slice(0, f.path.lastIndexOf("/")) : "";
    folders.set(dir, [...(folders.get(dir) ?? []), f]);
  }
  const recent: CatalogFile[] = [];
  for (const files of folders.values()) {
    files.sort((a, b) => (when(a) === when(b) ? b.mtime - a.mtime : when(a) < when(b) ? 1 : -1));
    recent.push(...files.slice(0, opts.perFolder ?? 4));
  }
  recent.sort((a, b) => (when(a) === when(b) ? b.mtime - a.mtime : when(a) < when(b) ? 1 : -1));
  for (const f of recent) out.push(foundFile(f));
  return out.slice(0, opts.max ?? 40);
}

/** One line per candidate for a prompt: "- path · 2026-11-02 · 전사본 · 35KB (앞 화면 [2])". */
export function candidateLines(files: Candidate[]): string {
  return files.map((f) => `- ${f.path} · ${[f.date, f.kind, `${Math.max(1, Math.round(f.bytes / 1024))}KB`].filter(Boolean).join(" · ")}${f.note ? ` (${f.note})` : ""}`).join("\n");
}

/** What a download response says the file is called: an ASCII fallback plus the UTF-8 name (RFC 6266/5987). */
export function contentDisposition(name: string): string {
  const ascii = name.replace(/[^\x20-\x7e]/g, "_").replace(/["\\]/g, "_");
  return `attachment; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(name)}`;
}
