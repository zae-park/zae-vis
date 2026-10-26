// Context for a search hit: where it came from (source, date, section, author) and the passage of
// the chunk that best matches the query. AutoRAG Lite returns whole chunks (up to ~4K chars) with no
// highlight, and a file path like sources/git/2026-10-26.md — everything shown is derived from those.

export type HitKind = "git" | "claude-code" | "shell-history" | "transcripts" | "custom" | "log" | "project" | "summary" | "inbox" | "other";

export type HitContext = {
  kind: HitKind;
  /** Korean label for the UI: "git 커밋", "Claude Code 세션", "한 줄 기록" … */
  sourceLabel: string;
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
  "shell-history": "터미널 명령",
  transcripts: "회의 전사본",
};

const NOISE_LINE = /^\s*$|^<!--|^#\s|^\s*-{3,}\s*$/;

/** Path → kind, label, date. Paths are relative to the worklog root (sources/git/2026-10-26.md). */
export function classifyPath(path: string): { kind: HitKind; sourceLabel: string; date: string | null } {
  // The worklog folders are matched anywhere in the path: AutoRAG may hand back an absolute path
  // the server could not shorten (e.g. /private/tmp/… vs /tmp/…).
  const p = path.replace(/^\/+/, "");
  const file = p.split("/").pop() ?? p;
  const date = /(\d{4}-\d{2}-\d{2})/.exec(file)?.[1] ?? /(\d{4}-\d{2})(?!\d)/.exec(file)?.[1] ?? null;
  let m: RegExpExecArray | null;
  if ((m = /(?:^|\/)sources\/([^/]+)\/[^/]+$/.exec(p))) {
    const name = m[1];
    if (name in SOURCE_LABELS) return { kind: name as HitKind, sourceLabel: SOURCE_LABELS[name], date };
    return { kind: "custom", sourceLabel: `${name} (커넥터)`, date };
  }
  if (/(?:^|\/)log\/[^/]+$/.test(p)) return { kind: "log", sourceLabel: "한 줄 기록", date };
  if (/(?:^|\/)projects\/[^/]+$/.test(p)) return { kind: "project", sourceLabel: "프로젝트", date: null };
  if (/(?:^|\/)summaries\/[^/]+$/.test(p)) return { kind: "summary", sourceLabel: "월간 정리", date };
  if (/(?:^|\/)(inbox|processed)\//.test(p)) return { kind: "inbox", sourceLabel: /transcripts/.test(p) ? "회의 전사본" : "inbox", date };
  return { kind: "other", sourceLabel: "worklog", date };
}

/** Query → terms worth matching: words of 2+ chars, plus Korean bigrams so particles don't block a match. */
export function queryTerms(query: string): string[] {
  const words = query.toLowerCase().split(/[\s,.;:!?()[\]{}"'`]+/).filter((w) => w.length >= 2);
  const out = new Set<string>();
  for (const w of words) {
    out.add(w);
    if (/[ㄱ-힝]/.test(w) && w.length >= 3) {
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
  const whole = query.toLowerCase().split(/\s+/).filter((w) => w.length >= 2);
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

export function describeHit(path: string, content: string, query: string): HitContext {
  const { kind, sourceLabel, date } = classifyPath(path);
  const { passage, matched, lineIndex } = bestPassage(content, query);
  const section = sectionAbove(content, lineIndex);
  const author = kind === "git" ? gitAuthor(passage) : null;
  return { kind, sourceLabel, date, section, author, passage, matched };
}
