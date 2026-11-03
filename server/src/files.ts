// Finding worklog files from a sentence ("11월 2일 전사본 내려받아 줘") so the chat can offer them as downloads.
// Only existing .md/.txt files are listed; nothing here writes.

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

type Kind = { label: string; dirs: string[]; words: string[] };

/** Which folders a word in the request points at. Order matters: the first kind whose folder holds a file names it. */
const KINDS: Kind[] = [
  // sources/transcripts/<date>.md only lists the day's transcript names: never what someone asking for one wants
  { label: "전사본", dirs: ["inbox/transcripts", "processed/transcripts"], words: ["전사", "녹음", "회의", "미팅", "meeting", "transcript"] },
  { label: "git 커밋", dirs: ["sources/git"], words: ["git", "깃", "커밋", "commit"] },
  { label: "셸 이력", dirs: ["sources/shell-history"], words: ["셸", "쉘", "shell", "zsh", "터미널"] },
  { label: "에이전트 세션", dirs: ["sources/agent-sessions", "sources/claude-code", "inbox/claude-sessions", "processed/claude-sessions"], words: ["에이전트", "세션", "claude", "클로드", "codex", "gemini"] },
  { label: "일간 리포트", dirs: ["reports/daily"], words: ["일간"] },
  { label: "주간 리포트", dirs: ["reports/weekly"], words: ["주간"] },
  { label: "월간 정리", dirs: ["summaries"], words: ["월간"] },
  { label: "리포트", dirs: ["reports", "summaries"], words: ["리포트", "보고서", "report"] },
  { label: "한 줄 기록", dirs: ["log"], words: ["로그", "한 줄 기록", "log"] },
  { label: "프로젝트", dirs: ["projects"], words: ["프로젝트", "project"] },
];

/** Word stems that only say "give me the file"; a leftover word starting with one is not part of what to look for. */
const FILLER = [
  "다운", "내려받", "받아", "받고", "받을", "받기", "저장", "내보내", "export", "download", "파일", "txt", "md", "텍스트", "원문",
  "해줘", "해주", "줘", "주세요", "줄래", "싶", "좀", "이거", "그거", "가장", "최근", "최신", "마지막", "방금", "제일", "있는", "했던", "만든",
];

const PARTICLE = /(을|를|이|가|은|는|의|로|으로|에서|에|만|도|하고|랑)$/;

/** Whether [path] contains [word] as written or without a trailing particle ("rosetta를" → "rosetta"). */
function mentions(path: string, word: string): boolean {
  if (path.includes(word)) return true;
  const stem = word.replace(PARTICLE, "");
  return stem.length >= 2 && stem !== word && path.includes(stem);
}

export function kindOf(path: string): string {
  for (const k of KINDS) if (k.dirs.some((d) => path === d || path.startsWith(`${d}/`))) return k.label;
  const m = /^sources\/([^/]+)\//.exec(path);
  return m ? m[1] : path.split("/")[0] ?? "";
}

function dateOf(name: string): string | null {
  return /(\d{4}-\d{2}-\d{2})/.exec(name)?.[1] ?? /(\d{4}-\d{2})(?!-\d)/.exec(name)?.[1] ?? null;
}

const pad = (n: number) => String(n).padStart(2, "0");
const ymd = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

type Wanted = { days: string[]; months: string[]; time: string | null; kinds: Kind[]; sourceDirs: string[]; tokens: string[]; latest: boolean };

/** Splits a request into dates, a time of day, kinds of record and leftover words. */
export function parseRequest(q: string, now: Date, sourceNames: string[] = []): Wanted {
  let rest = ` ${q.toLowerCase()} `;
  const days: string[] = [];
  const months: string[] = [];
  const take = (re: RegExp, f: (m: RegExpExecArray) => void) => {
    rest = rest.replace(re, (...args) => {
      f(args.slice(0, -2) as unknown as RegExpExecArray);
      return " ";
    });
  };
  const yearFor = (month: number) => (month > now.getMonth() + 1 ? now.getFullYear() - 1 : now.getFullYear());
  take(/(\d{4})[-./](\d{1,2})[-./](\d{1,2})/g, (m) => days.push(`${m[1]}-${pad(+m[2])}-${pad(+m[3])}`));
  take(/(\d{1,2})\s*월\s*(\d{1,2})\s*일/g, (m) => days.push(`${yearFor(+m[1])}-${pad(+m[1])}-${pad(+m[2])}`));
  take(/(?<![\d.])(\d{1,2})\/(\d{1,2})(?![\d/])/g, (m) => days.push(`${yearFor(+m[1])}-${pad(+m[1])}-${pad(+m[2])}`));
  take(/(\d{4})-(\d{2})(?!-?\d)/g, (m) => months.push(`${m[1]}-${m[2]}`));
  take(/(?<!\d)(\d{1,2})\s*월(?!\s*\d)/g, (m) => months.push(`${yearFor(+m[1])}-${pad(+m[1])}`));
  const shift = (d: number) => ymd(new Date(now.getFullYear(), now.getMonth(), now.getDate() - d));
  take(/오늘/g, () => days.push(shift(0)));
  take(/어제/g, () => days.push(shift(1)));
  take(/그제|그저께/g, () => days.push(shift(2)));
  let time: string | null = null;
  take(/(?<!\d)(\d{1,2}):(\d{2})(?!\d)/g, (m) => (time = `${pad(+m[1])}${m[2]}`));
  take(/(?<!\d)(\d{1,2})\s*시(?:\s*(\d{1,2})\s*분)?/g, (m) => (time = m[2] ? `${pad(+m[1])}${pad(+m[2])}` : pad(+m[1])));
  const latest = /가장\s*최근|최신|마지막|방금|제일\s*최근|최근/.test(q);

  const kinds: Kind[] = [];
  for (const k of KINDS) {
    for (const w of k.words) {
      if (rest.includes(w)) {
        if (!kinds.includes(k)) kinds.push(k);
        rest = rest.split(w).join(" ");
      }
    }
  }
  // a specific kind (일간) wins over the general one (리포트)
  const specific = kinds.filter((k) => !kinds.some((o) => o !== k && o.dirs.every((d) => k.dirs.some((kd) => d.startsWith(`${kd}/`)))));
  const sourceDirs = sourceNames.filter((s) => s.length >= 3 && rest.includes(s.toLowerCase()));
  for (const s of sourceDirs) rest = rest.split(s.toLowerCase()).join(" ");
  const tokens = rest
    .split(/[\s,.·!?()[\]"'“”‘’]+/)
    .filter((t) => t.length >= 2 && !/^\d+$/.test(t) && !FILLER.some((f) => t.startsWith(f)));
  return { days, months, time, kinds: specific, sourceDirs, tokens, latest };
}

/**
 * The files a request names, best first: an exact path or file name; otherwise files that fit every date, time and
 * kind it mentions and as many of its leftover words as possible. Empty when the request names nothing concrete.
 */
export function findFiles(catalog: CatalogFile[], q: string, now = new Date(), limit = 10): FoundFile[] {
  const found = (f: CatalogFile): FoundFile => ({ path: f.path, name: f.name, bytes: f.bytes, date: dateOf(f.name), kind: kindOf(f.path) });
  const lower = q.toLowerCase();
  const exact = catalog.filter((f) => lower.includes(f.path.toLowerCase()) || (f.name.length >= 5 && lower.includes(f.name.toLowerCase())));
  if (exact.length) return exact.slice(0, limit).map(found);

  const sourceNames = [...new Set(catalog.map((f) => /^sources\/([^/]+)\//.exec(f.path)?.[1]).filter((s): s is string => !!s))];
  const w = parseRequest(q, now, sourceNames);
  const constrained = w.days.length > 0 || w.months.length > 0 || w.time !== null || w.kinds.length > 0 || w.sourceDirs.length > 0;
  const scored: Array<{ f: CatalogFile; score: number; date: string }> = [];
  for (const f of catalog) {
    const p = f.path.toLowerCase();
    if (w.kinds.length && !w.kinds.some((k) => k.dirs.some((d) => p.startsWith(`${d}/`)))) continue;
    if (w.sourceDirs.length && !w.sourceDirs.some((s) => p.startsWith(`sources/${s.toLowerCase()}/`))) continue;
    const date = dateOf(f.name) ?? "";
    if (w.days.length && !w.days.some((d) => date === d || (date.length === 7 && d.startsWith(date)))) continue;
    if (w.months.length && !w.months.some((m) => date.startsWith(m))) continue;
    if (w.time && !new RegExp(`[_ T-]${w.time}`).test(f.name)) continue;
    const score = w.tokens.filter((t) => mentions(p, t)).length;
    if (!constrained && score === 0) continue;
    scored.push({ f, score, date: date || new Date(f.mtime).toISOString().slice(0, 10) });
  }
  // when some names match the leftover words, the ones that match none are noise ("rosetta 프로젝트" is not every project)
  if (scored.some((s) => s.score > 0)) scored.splice(0, scored.length, ...scored.filter((s) => s.score > 0));
  scored.sort((a, b) => b.score - a.score || (a.date === b.date ? b.f.mtime - a.f.mtime : a.date < b.date ? 1 : -1) || a.f.path.localeCompare(b.f.path));
  return scored.slice(0, w.latest ? 1 : limit).map((s) => found(s.f));
}

/**
 * The files a question is about by name rather than by content: a kind of record plus a date, a time or "latest"
 * ("가장 최근 회의록 요약해줘", "11월 2일 전사본에서 정한 것"). Search cannot see "latest", so the asker reads these whole.
 */
export function filesNamedIn(catalog: CatalogFile[], q: string, now = new Date(), limit = 3): FoundFile[] {
  const w = parseRequest(q, now);
  if (!w.kinds.length || !(w.latest || w.days.length || w.months.length || w.time)) return [];
  return findFiles(catalog, q, now, limit);
}

/** What a download response says the file is called: an ASCII fallback plus the UTF-8 name (RFC 6266/5987). */
export function contentDisposition(name: string): string {
  const ascii = name.replace(/[^\x20-\x7e]/g, "_").replace(/["\\]/g, "_");
  return `attachment; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(name)}`;
}
