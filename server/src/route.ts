// Chat routing with Jev (TypeSafe's decision model, through the OpenRouter key the user saved). Jev answers typed
// questions about a state with an option and a confidence and never writes text, so one call (~0.3 s) says what a
// chat line wants — a lookup, an answer, or a file — and which listed file it means. Used only when an OpenRouter key
// is saved; without one, or when Jev is unsure or unreachable, the answering agent decides (ask.ts).

import { Jev, OpenRouterBackend, pick, type Question, type State, type Verdict } from "jev-use";
import type { Candidate } from "./files.ts";

/** OpenRouter's live Jev id (jev-use's own default, `typesafe/jev-latest`, is rejected there; AutoRAG pins the same). */
export const JEV_MODEL = "typesafe/jev-1.13";
/** One attempt, short: a slow router must not hold up the answer it is meant to speed up. */
const JEV_TIMEOUT_MS = 5000;

export type ChatIntent = "search" | "answer" | "files";
/** Jev's decision for one line. `files` are paths from the candidates; for `answer` they are read in whole as sources. */
export type ChatRoute = { intent: ChatIntent; files: string[]; confidence: number; ms: number };

/** One batched Jev judgment; tests pass a fake. */
export type Judge = (state: State, questions: Record<string, Question>) => Promise<{ answers: Record<string, Verdict> }>;

export function jevJudge(apiKey: string): Judge {
  const jev = new Jev({ backend: new OpenRouterBackend({ apiKey, defaultModel: JEV_MODEL, timeoutMs: JEV_TIMEOUT_MS, maxRetries: 0 }) });
  return (state, questions) => jev.judge(state, questions);
}

const INTENTS = {
  search: "a lookup by keywords: the user wants to see the matching records, no written answer",
  answer: "a question or request answered in sentences from the records (what happened, why, a summary, a comparison)",
  files: "the file itself handed over to save or download (a transcript, report, log or note file), not its content written out",
} as const;

/**
 * What [line] wants and which candidate file it points at. Null when Jev escalates the intent, or names "files"
 * without a confident file — the agent decides then.
 */
export async function routeLine(judge: Judge, line: string, opts: { candidates: Candidate[]; previous?: { q: string; answer: string }[]; today?: string }): Promise<ChatRoute | null> {
  const started = Date.now();
  const ids = opts.candidates.map((_, i) => `f${i + 1}`);
  const state = {
    task: "Route one line typed into the chat of a personal work log (Korean). The files are the log's own, newest first.",
    today: opts.today ?? new Date().toISOString().slice(0, 10),
    previous: (opts.previous ?? []).slice(-2).map((t) => ({ user: t.q, reply: t.answer.slice(0, 300) })),
    line,
    files: opts.candidates.map((f, i) => ({ id: ids[i], path: f.path, date: f.date, kind: f.kind, ...(f.note ? { shown: f.note } : {}) })),
  };
  const questions: Record<string, Question> = { intent: pick("What does the user want from this line?", INTENTS) };
  if (ids.length) {
    const options: Record<string, string> = { none: "the line is not about one particular listed file" };
    opts.candidates.forEach((f, i) => (options[ids[i]] = `${f.path} (${[f.date, f.kind].filter(Boolean).join(", ")})`));
    questions.file = pick("Which one listed file does the line point at, if any?", options);
  }
  let answers: Record<string, Verdict>;
  try {
    ({ answers } = await judge(state, questions));
  } catch {
    return null; // no backend, bad key: the agent routes
  }
  const intent = answers.intent;
  if (!intent || intent.escalate || !(String(intent.answer) in INTENTS)) return null;
  const file = answers.file;
  const picked = file && !file.escalate && typeof file.answer === "string" && file.answer !== "none" ? opts.candidates[ids.indexOf(file.answer)]?.path : undefined;
  const kind = intent.answer as ChatIntent;
  if (kind === "files" && !picked) return null;
  return { intent: kind, files: picked ? [picked] : [], confidence: intent.confidence, ms: Date.now() - started };
}
