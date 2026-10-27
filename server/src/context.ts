// Context for a search hit: where it came from (source, date, section, author) and the passage of
// the chunk that best matches the query. AutoRAG Lite returns whole chunks (up to ~4K chars) with no
// highlight, and a file path like sources/git/2026-10-26.md — everything shown is derived from those.

import { datasourceLabel, TEMPLATES } from "./datasources.ts";

export type HitKind = "git" | "claude-code" | "shell-history" | "transcripts" | "custom" | "log" | "project" | "summary" | "inbox" | "external" | "other";

export type HitContext = {
  kind: HitKind;
  /** Korean label for the UI: "git 커밋", "Claude Code 세션", "한 줄 기록", "Obsidian 볼트" … */
  sourceLabel: string;
  /** External AutoRAG datasource the hit came from (config key such as "obsidian", "slack"); null for worklog hits. */
  datasource: string | null;
  /** Absolute path of the original behind an external hit, when the datasource has one (Obsidian notes). */
  file: string | null;
  /** YYYY-MM-DD, or YYYY-MM for monthly files; null when the path has no date. */
  date: string | null;
  /** Nearest "## " heading above the passage: repository, session title, project name … */
  section: string | null;
  /** Commit author on the matched line (git source only). */
  author: string | null;
  /** The best-matching passage of the chunk, a few lines around the strongest match. */
  passage: string;
  /** Query terms found in the passage (for highlighting). Empty for purely semantic hits. */
  matched: string[];
};

const SOURCE_LABELS: Record<string, string> = {
  git: "git 커밋",
  "claude-code": "Claude Code 세션",
  "agent-sessions": "에이전트 세션",
  "shell-history": "터미널 명령",
  transcripts: "회의 전사본",
};

const NOISE_LINE = /^\s*$|^<!--|^#\s|^\s*-{3,}\s*$/;

const TEMPLATE_IDS = new Set(TEMPLATES.map((t) => t.name));

/**
 * Path → kind, label, date. Paths are relative to the worklog root (sources/git/2026-10-26.md), or an
 * AutoRAG datasource source ("/obsidian/default/노트.md", "/slack/default/C01/…") — `datasourceId`
 * says so for sure; without it, a leading segment that is a known template name is taken as one.
 */
export function classifyPath(path: string, datasourceId?: string | null): { kind: HitKind; sourceLabel: string; date: string | null; datasource: string | null } {
  const file = path.split("/").pop() ?? path;
  const date = /(\d{4}-\d{2}-\d{2})/.exec(file)?.[1] ?? /(\d{4}-\d{2})(?!\d)/.exec(file)?.[1] ?? null;
  const external = datasourceId || (/^\/([^/]+)\//.test(path) && TEMPLATE_IDS.has(path.split("/")[1]) ? path.split("/")[1] : null);
  // external sources carry the date in any segment ("/slack/default/C01/2026-10-20/p1.md"), not just the file name
  if (external) return { kind: "external", sourceLabel: datasourceLabel(external), date: date ?? /(\d{4}-\d{2}-\d{2})/.exec(path)?.[1] ?? null, datasource: external };
  // The worklog folders are matched anywhere in the path: AutoRAG may hand back an absolute path
  // the server could not shorten (e.g. /private/tmp/… vs /tmp/…).
  const p = path.replace(/^\/+/, "");
  let m: RegExpExecArray | null;
  const local = (kind: HitKind, sourceLabel: string, d: string | null = date) => ({ kind, sourceLabel, date: d, datasource: null });
  if ((m = /(?:^|\/)sources\/([^/]+)\/[^/]+$/.exec(p))) {
    const name = m[1];
    if (name in SOURCE_LABELS) return local(name as HitKind, SOURCE_LABELS[name]);
    return local("custom", `${name} (커넥터)`);
  }
  if (/(?:^|\/)log\/[^/]+$/.test(p)) return local("log", "한 줄 기록");
  if (/(?:^|\/)projects\/[^/]+$/.test(p)) return local("project", "프로젝트", null);
  if (/(?:^|\/)summaries\/[^/]+$/.test(p)) return local("summary", "월간 정리");
  if (/(?:^|\/)(inbox|processed)\//.test(p)) return local("inbox", /transcripts/.test(p) ? "회의 전사본" : "inbox");
  return local("other", "worklog");
}

// Korean particles and endings stripped from the end of a query word, longest first, so that
// "음성에서" → "음성", "모으는" → "모으", "자동으로" → "자동". Not a morphological analyser — just enough
// that highlighting and passage picking follow content words rather than grammar.
const KO_SUFFIXES = [
  "에서는", "으로는", "에게서", "한테서", "으로써", "으로서",
  "에서", "으로", "에게", "한테", "까지", "부터", "처럼", "보다", "마다", "조차", "라도", "이나", "에는", "에도", "로는", "로도", "와는", "과는", "하는", "되는", "하고", "이다", "였다", "했다", "하기", "되기",
  "은", "는", "이", "가", "을", "를", "의", "에", "와", "과", "도", "로", "만", "들", "요", "며", "고", "면",
];
const HANGUL = /[ㄱ-힝]/;

export function stemKo(word: string): string {
  if (!HANGUL.test(word)) return word;
  for (const s of KO_SUFFIXES) {
    if (word.length - s.length >= 2 && word.endsWith(s)) return word.slice(0, -s.length);
  }
  return word;
}

/** Query → terms worth matching: content words (Korean particles stripped), plus bigrams of long Korean words. */
export function queryTerms(query: string): string[] {
  const words = query.toLowerCase().split(/[\s,.;:!?()[\]{}"'`]+/).map(stemKo).filter((w) => w.length >= 2);
  const out = new Set<string>();
  for (const w of words) {
    out.add(w);
    if (HANGUL.test(w) && w.length >= 4) {
      for (let i = 0; i + 2 <= w.length; i++) out.add(w.slice(i, i + 2));
    }
  }
  return [...out];
}

function lineScore(line: string, terms: string[], whole: string[]): { score: number; matched: string[] } {
  const l = line.toLowerCase();
  const matched: string[] = [];
  let score = 0;
  for (const t of terms) {
    if (l.includes(t)) {
      matched.push(t);
      score += whole.includes(t) ? 3 : 1; // a whole query word beats a bigram
    }
  }
  return { score, matched };
}

/**
 * Picks the window of `content` that matches `query` best. Pure-semantic hits (no term in common) get
 * the first substantive lines of the chunk instead of its header.
 */
export function bestPassage(content: string, query: string, maxChars = 420): { passage: string; matched: string[]; lineIndex: number } {
  const lines = content.split("\n");
  const terms = queryTerms(query);
  const whole = query.toLowerCase().split(/\s+/).map(stemKo).filter((w) => w.length >= 2);
  let best = -1;
  let bestScore = 0;
  let bestMatched: string[] = [];
  lines.forEach((line, i) => {
    if (NOISE_LINE.test(line)) return;
    const { score, matched } = lineScore(line, terms, whole);
    if (score > bestScore) {
      best = i;
      bestScore = score;
      bestMatched = matched;
    }
  });
  if (best < 0) {
    best = lines.findIndex((l) => !NOISE_LINE.test(l) && !/^##\s/.test(l));
    if (best < 0) best = 0;
  }
  // grow the window around the best line, preferring following lines (a heading's details come after it)
  const picked: string[] = [lines[best].trim()];
  let lo = best;
  let hi = best;
  let size = picked[0].length;
  // blank lines are skipped over, so a matching heading still brings its details along
  while (size < maxChars) {
    while (hi + 1 < lines.length && lines[hi + 1].trim() === "") hi++;
    while (lo - 1 >= 0 && lines[lo - 1].trim() === "") lo--;
    const next = hi + 1 < lines.length && !/^##\s/.test(lines[hi + 1]) && !NOISE_LINE.test(lines[hi + 1]) ? lines[hi + 1].trim() : null;
    const prev = lo - 1 >= 0 && !NOISE_LINE.test(lines[lo - 1]) && !/^##\s/.test(lines[lo - 1]) ? lines[lo - 1].trim() : null;
    if (next !== null && size + next.length <= maxChars) {
      picked.push(next);
      hi++;
      size += next.length + 1;
    } else if (prev !== null && size + prev.length <= maxChars) {
      picked.unshift(prev);
      lo--;
      size += prev.length + 1;
    } else break;
  }
  let passage = picked.join("\n");
  if (passage.length > maxChars) passage = passage.slice(0, maxChars).trimEnd() + "…";
  // report whole words first, then the bigrams that only matter for highlighting
  const matched = [...new Set(bestMatched)].sort((a, b) => b.length - a.length);
  return { passage, matched, lineIndex: best };
}

/** Nearest "## heading" above `lineIndex`, without markdown decoration. */
export function sectionAbove(content: string, lineIndex: number): string | null {
  const lines = content.split("\n");
  for (let i = Math.min(lineIndex, lines.length - 1); i >= 0; i--) {
    const m = /^##\s+(.+?)\s*$/.exec(lines[i]);
    if (m) return m[1].replace(/`/g, "");
  }
  return null;
}

/** Author from a git line: "- 11:17 `abc1234` subject (3 files, +1 −0) — 이름". */
export function gitAuthor(passage: string): string | null {
  for (const line of passage.split("\n")) {
    const m = /^- \d{2}:\d{2} `[0-9a-f]{7}` .* — ([^—\n]+)$/.exec(line.trim());
    if (m) return m[1].trim();
  }
  return null;
}

/** Extra facts AutoRAG attaches to an external datasource hit (metadata.datasourceId / path / title). */
export type ExternalHit = { datasourceId: string; file?: string | null; title?: string | null };

export function describeHit(path: string, content: string, query: string, passageChars = 420, external?: ExternalHit): HitContext {
  const { kind, sourceLabel, date, datasource } = classifyPath(path, external?.datasourceId);
  const { passage, matched, lineIndex } = bestPassage(content, query, passageChars);
  // an external note has no "## section" convention; its title (metadata) is the best context
  const section = sectionAbove(content, lineIndex) ?? (kind === "external" ? external?.title ?? null : null);
  const author = kind === "git" ? gitAuthor(passage) : null;
  return { kind, sourceLabel, datasource, file: external?.file ?? null, date, section, author, passage, matched };
}
