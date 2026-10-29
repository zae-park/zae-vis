// Extra folders (a memory notebook that is not the worklog) joined into AutoRAG's searchPaths.
// The worklog stays the first root. AutoRAG names two folders with the same basename /worklog and
// /worklog-2 in sorted-path order; displayPath uses that same naming so a hit opens the right file.

import { existsSync, readFileSync, realpathSync, statSync } from "node:fs";
import { basename, resolve, sep } from "node:path";
import type { AppConfig } from "./config.ts";
import { writeJson } from "./config.ts";

/** Worklog first, then each extra folder once. */
export function indexRoots(cfg: Pick<AppConfig, "worklogDir" | "memoryPaths">): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const p of [cfg.worklogDir, ...cfg.memoryPaths]) {
    const abs = resolve(p);
    if (seen.has(abs)) continue;
    seen.add(abs);
    out.push(abs);
  }
  return out;
}

/** Virtual prefixes AutoRAG assigns (`/worklog`, `/worklog-2`), in its sorted-path order. */
export function sourcePrefixes(roots: string[]): { root: string; prefix: string }[] {
  const sorted = [...new Set(roots.map((r) => resolve(r)))].sort((a, b) => a.localeCompare(b));
  const used = new Set<string>();
  return sorted.map((root) => {
    const base = basename(root) || "root";
    let prefix = `/${base}`;
    let n = 2;
    while (used.has(prefix)) {
      prefix = `/${base}-${n++}`;
    }
    used.add(prefix);
    return { root, prefix };
  });
}

/**
 * Writes `searchPaths` in AutoRAG's config to the worklog plus memory folders.
 * Other keys stay. No file yet (setup not run) → nothing to do.
 */
export function syncSearchPaths(cfg: Pick<AppConfig, "worklogDir" | "memoryPaths" | "autoragConfig">): boolean {
  if (!existsSync(cfg.autoragConfig)) return false;
  const raw = JSON.parse(readFileSync(cfg.autoragConfig, "utf8")) as Record<string, unknown>;
  const next = indexRoots(cfg);
  const cur = Array.isArray(raw.searchPaths) ? raw.searchPaths.map((p) => resolve(String(p))) : [];
  if (cur.length === next.length && cur.every((p, i) => p === next[i])) return false;
  raw.searchPaths = next;
  writeJson(cfg.autoragConfig, raw);
  return true;
}

/** A .md/.txt under one of the index roots. Relative paths are the worklog's job. */
export function readIndexedFile(rel: string, roots: string[]): { path: string; markdown: string } | null {
  if (!rel.startsWith("/") || !/\.(md|txt)$/i.test(rel)) return null;
  let abs: string;
  try {
    abs = realpathSync(resolve(rel));
  } catch {
    return null;
  }
  for (const root of roots) {
    let home: string;
    try {
      home = realpathSync(resolve(root));
    } catch {
      continue;
    }
    const bound = home.endsWith(sep) ? home : home + sep;
    if (abs !== home && !abs.startsWith(bound)) continue;
    if (!statSync(abs).isFile()) return null;
    return { path: abs, markdown: readFileSync(abs, "utf8") };
  }
  return null;
}

/** True when `p` is a directory that is not the worklog and not the whole home folder. */
export function acceptMemoryPath(p: string, worklogDir: string, home: string): string {
  const abs = resolve(p);
  if (abs === resolve(worklogDir)) throw new Error("기록 폴더는 이미 색인됩니다.");
  if (abs === resolve(home) || abs === "/") throw new Error("홈 폴더 전체는 색인하지 않습니다. 노트가 있는 폴더를 지정하세요.");
  if (!existsSync(abs) || !statSync(abs).isDirectory()) throw new Error(`폴더가 없습니다: ${abs}`);
  return abs;
}
