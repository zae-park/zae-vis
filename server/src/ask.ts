// "질문" (ask): answers a question from the worklog. The search (AutoRAG Lite: BM25 + local vectors)
// picks the passages; an agent the user already has writes the answer from those passages only, with
// [n] citations. The agent is chosen exactly as for the weekly digest (digest.ts): an installed CLI —
// Claude Code, Codex, Gemini — or the saved OpenRouter key. Setting `digest.agent` / `digest.model`
// applies here too, so there is nothing new to configure.
//
// CLIs run with the worklog as cwd but with their tools off (Claude `--tools ""`, Codex
// `--sandbox read-only`, Gemini without `--yolo`), so a question can never change a file.
//
// Questions belong to conversations: a follow-up carries the previous turns (question + answer)
// into the prompt, and a short follow-up ("그건 왜?") is searched together with the previous
// question so the passages fit. Conversations are kept in `$ZAEVIS_HOME/ask/<id>.json`.

import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { stateDir } from "./config.ts";
import { spawn } from "node:child_process";
import { delimiter } from "node:path";
import type { SearchBackend, SearchHit } from "./autorag.ts";
import { DEFAULT_OPENROUTER_MODEL, noAgentReason, searchDirs, type AgentId, type AgentInfo, type DigestSetting } from "./digest.ts";
import { getKey as openrouterKey } from "./rerank.ts";
import { fallbackCandidates, plannedRail, quotaReason, withStop, type RailStop } from "./rail.ts";

export type AskSource = { n: number; path: string; label: string; passage: string };
export type AskResult = { q: string; answer: string; sources: AskSource[]; agent: AgentId; ms: number; at: string; conversationId: string; turn: number; rail?: RailStop[] };
export type Conversation = { id: string; title: string; createdAt: string; updatedAt: string; turns: AskResult[] };
export type ConversationSummary = Pick<Conversation, "id" | "title" | "createdAt" | "updatedAt"> & { turns: number };
export type AskError = { status: 400 | 404 | 409 | 502; error: "missing_query" | "no_hits" | "no_agent" | "busy" | "search_failed" | "agent_failed"; message: string; rail?: RailStop[] };
export type AskOutcome = { ok: true; result: AskResult } | ({ ok: false } & AskError);

export const DEFAULT_TOP_K = 10;
export const MAX_TOP_K = 20;
/** Longer than the 420 chars a search card shows: the model needs the surrounding lines too. */
export const PASSAGE_CHARS = 1000;
const RUN_TIMEOUT_MS = 3 * 60_000;

/** Previous turns included in a follow-up prompt, and how much of each answer. */
const HISTORY_TURNS = 4;
const HISTORY_ANSWER_CHARS = 600;
/** A follow-up this short is searched together with the previous question ("그건 왜?"). */
const SHORT_FOLLOWUP_CHARS = 16;
const MAX_CONVERSATIONS = 50;

export const NO_AGENT_MESSAGE = "답을 쓸 에이전트가 없습니다. Claude Code·Codex·Gemini CLI 중 하나를 설치하거나 설정 → 검색 결과 재정렬에서 OpenRouter 키를 저장하세요.";

// ── prompt ─────────────────────────────────────────────────────────────────────

/** Search hits → numbered sources. Weak hits are dropped when there is anything better. */
export function pickSources(hits: SearchHit[], max = DEFAULT_TOP_K): AskSource[] {
  const strong = hits.filter((h) => !h.weak);
  const chosen = (strong.length ? strong : hits).slice(0, max);
  return chosen.map((h, i) => ({
    n: i + 1,
    path: h.path,
    // a session title can be a whole paragraph: keep the label one line
    label: [h.context?.date, h.context?.sourceLabel, clipLabel(h.context?.section), h.context?.author].filter(Boolean).join(" · ") || h.title,
    passage: h.snippet,
  }));
}

const clipLabel = (s: string | null | undefined): string | null => (!s ? null : s.length > 60 ? s.slice(0, 60).trimEnd() + "…" : s);

export function buildAskPrompt(q: string, sources: AskSource[], history: Pick<AskResult, "q" | "answer">[] = []): string {
  const list = sources.map((s) => `[${s.n}] (${s.label}) ${s.path}\n${s.passage}`).join("\n\n");
  const prior = history.slice(-HISTORY_TURNS);
  const dialogue = prior.length
    ? `\n이전 대화 (참고용 — 번호 [n]은 이번 발췌 기준으로 새로 단다):\n${prior.map((t) => `사용자: ${t.q}\n답: ${clipText(t.answer, HISTORY_ANSWER_CHARS)}`).join("\n\n")}\n`
    : "";
  return `아래 발췌는 내 작업 기록(worklog)에서 질문과 관련 있어 검색된 문단이다. 이 발췌만 근거로 질문에 한국어로 답한다.

규칙:
- 각 문장 끝에 근거가 된 발췌 번호를 [n] 꼴로 단다. 여러 발췌가 근거면 [1][3]처럼 붙인다.
- 발췌에 없는 내용은 쓰지 않는다. 발췌로 답할 수 없으면 "기록에서 근거를 찾지 못했습니다."라고 쓰고, 가장 가까운 내용이 있으면 그것만 한 문장으로 덧붙인다.
- 파일을 열거나 명령을 실행하지 않는다. 서론·제목·인사 없이 답만 쓴다 (5문장 이내, 필요하면 짧은 목록).${prior.length ? "\n- 이전 대화의 맥락을 이어받되(예: \"그건\"이 가리키는 것), 근거는 이번 발췌에서만 든다." : ""}
${dialogue}
질문: ${q}

발췌:
${list}`;
}

const clipText = (s: string, max: number): string => (s.length > max ? s.slice(0, max).trimEnd() + "…" : s);

/** What to search for: a short follow-up alone finds nothing, so the previous question rides along. */
export function searchQueryFor(q: string, previous?: string): string {
  return previous && q.length <= SHORT_FOLLOWUP_CHARS ? `${previous} ${q}` : q;
}

// ── conversations ──────────────────────────────────────────────────────────────

/** Conversations on disk: one JSON per id, newest-updated first in listings. */
export class ConversationStore {
  readonly dir: string;
  constructor(dir = join(stateDir(), "ask")) {
    this.dir = dir;
  }

  private file(id: string): string {
    if (!/^[0-9]{8}-[0-9]{6}(-[0-9a-z]+)?$/.test(id)) throw new Error("bad conversation id");
    return join(this.dir, `${id}.json`);
  }

  newId(now = new Date()): string {
    const p = (n: number) => String(n).padStart(2, "0");
    const base = `${now.getFullYear()}${p(now.getMonth() + 1)}${p(now.getDate())}-${p(now.getHours())}${p(now.getMinutes())}${p(now.getSeconds())}`;
    return existsSync(join(this.dir, `${base}.json`)) ? `${base}-${Math.random().toString(36).slice(2, 6)}` : base;
  }

  get(id: string): Conversation | null {
    const f = this.file(id); // throws on a malformed id
    try {
      return JSON.parse(readFileSync(f, "utf8")) as Conversation;
    } catch {
      return null;
    }
  }

  save(c: Conversation): void {
    mkdirSync(this.dir, { recursive: true });
    writeFileSync(this.file(c.id), JSON.stringify(c, null, 2));
    this.prune();
  }

  remove(id: string): boolean {
    const f = this.file(id);
    if (!existsSync(f)) return false;
    rmSync(f);
    return true;
  }

  list(): ConversationSummary[] {
    let names: string[];
    try {
      names = readdirSync(this.dir).filter((n) => n.endsWith(".json"));
    } catch {
      return [];
    }
    const out: ConversationSummary[] = [];
    for (const n of names) {
      const c = this.get(n.slice(0, -5));
      if (c) out.push({ id: c.id, title: c.title, createdAt: c.createdAt, updatedAt: c.updatedAt, turns: c.turns.length });
    }
    return out.sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : -1));
  }

  /** Keeps the newest MAX_CONVERSATIONS. */
  private prune(): void {
    for (const c of this.list().slice(MAX_CONVERSATIONS)) this.remove(c.id);
  }
}

/** Read-only invocations: the model may answer, not act. */
export function askCliArgs(agent: Exclude<AgentId, "openrouter">, prompt: string, extra: { outFile?: string } = {}): string[] {
  switch (agent) {
    case "claude":
      return ["-p", prompt, "--output-format", "text", "--tools", "", "--max-turns", "1"];
    case "codex":
      return ["exec", "--sandbox", "read-only", "--skip-git-repo-check", ...(extra.outFile ? ["-o", extra.outFile] : []), prompt];
    case "gemini":
      return ["-p", prompt];
  }
}

// ── running ────────────────────────────────────────────────────────────────────

export type Exec = (bin: string, args: string[], cwd: string, env?: NodeJS.ProcessEnv, timeoutMs?: number) => Promise<{ ok: boolean; stdout: string; stderr: string }>;

/** Like digest.runCli but keeps stdout (the answer) apart from stderr (progress chatter). */
export const execCli: Exec = (bin, args, cwd, env, timeoutMs = RUN_TIMEOUT_MS) =>
  new Promise((res) => {
    const child = spawn(bin, args, { cwd, env: { ...(env ?? process.env), PATH: searchDirs(env).join(delimiter), NO_COLOR: "1" }, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout?.on("data", (c: Buffer) => (stdout = (stdout + c.toString()).slice(-40_000)));
    child.stderr?.on("data", (c: Buffer) => (stderr = (stderr + c.toString()).slice(-10_000)));
    const t = setTimeout(() => {
      child.kill("SIGTERM");
      stderr += "\n[시간 초과]";
    }, timeoutMs);
    child.on("error", (e) => {
      clearTimeout(t);
      res({ ok: false, stdout, stderr: e.message });
    });
    child.on("close", (code) => {
      clearTimeout(t);
      res({ ok: code === 0, stdout: stdout.trim(), stderr: stderr.trim() });
    });
  });

export async function chatText(key: string, model: string, prompt: string, fetchImpl: typeof fetch = fetch, timeoutMs = RUN_TIMEOUT_MS): Promise<string> {
  const res = await fetchImpl("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: { authorization: `Bearer ${key}`, "content-type": "application/json", "HTTP-Referer": "https://github.com/zae-park/zaevis", "X-Title": "zaevis" },
    body: JSON.stringify({ model, messages: [{ role: "user", content: prompt }], temperature: 0.2 }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!res.ok) throw new Error(`OpenRouter HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const body = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> };
  return (body.choices?.[0]?.message?.content ?? "").trim();
}

/** Gemini prints "Loaded cached credentials." and similar before the answer; Claude's text mode is clean. */
export function cleanAnswer(text: string): string {
  return text
    .split("\n")
    .filter((l) => !/^(Loaded cached credentials\.?|YOLO mode is enabled.*|\[dotenv@.*)$/.test(l.trim()))
    .join("\n")
    .trim();
}

/** A failure that already knows which rail stops were tried, so the app can draw them. */
export class AgentFailed extends Error {
  readonly rail: RailStop[];
  constructor(message: string, rail: RailStop[]) {
    super(message);
    this.rail = rail;
  }
}

export class AskRunner {
  private running: { q: string; startedAt: string; agent: AgentId; conversationId: string | null; rail: RailStop[] } | null = null;
  private lastResult: AskResult | null = null;
  readonly store: ConversationStore;
  private readonly opts: { exec?: Exec; fetchImpl?: typeof fetch; env?: NodeJS.ProcessEnv; log?: (line: string) => void };

  constructor(opts: { exec?: Exec; fetchImpl?: typeof fetch; env?: NodeJS.ProcessEnv; log?: (line: string) => void; store?: ConversationStore } = {}) {
    this.opts = opts;
    this.store = opts.store ?? new ConversationStore();
  }

  status(): { running: { q: string; startedAt: string; agent: AgentId; conversationId: string | null; rail: RailStop[] } | null; last: AskResult | null; conversations: ConversationSummary[] } {
    return { running: this.running, last: this.lastResult, conversations: this.store.list() };
  }

  /**
   * One question at a time: a second one while an agent is working gets `busy`. With
   * `conversationId` the question continues that conversation (404-ish `missing_query`
   * is not raised for an unknown id: a new conversation starts instead).
   */
  async ask(q: string, opts: { search: SearchBackend; agent: AgentInfo | null; setting: Pick<DigestSetting, "model"> & { agent?: DigestSetting["agent"] }; worklogDir: string; topK?: number; conversationId?: string; /** all detected agents, so the no-agent message can name one that only needs a login, and auto can fall through on quota */ agents?: AgentInfo[] }): Promise<AskOutcome> {
    const question = q.trim();
    if (!question) return { ok: false, status: 400, error: "missing_query", message: "질문을 입력하세요." };
    if (!opts.agent) return { ok: false, status: 409, error: "no_agent", message: opts.agents ? `답을 쓸 ${noAgentReason(opts.agents)}` : NO_AGENT_MESSAGE };
    if (this.running) return { ok: false, status: 409, error: "busy", message: `아직 답을 만드는 중입니다: "${this.running.q.slice(0, 40)}"` };
    const topK = Math.min(Math.max(opts.topK ?? DEFAULT_TOP_K, 1), MAX_TOP_K);
    const started = Date.now();
    const existing = opts.conversationId ? this.store.get(opts.conversationId) : null;
    const mode = opts.setting.agent;
    const chain = mode === "auto" && opts.agents ? fallbackCandidates({ agent: "auto" }, opts.agents) : [opts.agent];
    const rail = mode && opts.agents ? plannedRail({ agent: mode }, opts.agents) : plannedRail({ agent: opts.agent.id }, [opts.agent]);
    this.running = { q: question, startedAt: new Date(started).toISOString(), agent: chain[0]?.id ?? opts.agent.id, conversationId: existing?.id ?? null, rail };
    try {
      const previous = existing?.turns.at(-1);
      // fetch a few more than needed so weak hits can be dropped
      const r = await opts.search.search(searchQueryFor(question, previous?.q), Math.min(topK + 5, 50), PASSAGE_CHARS);
      if (!r.ok) return { ok: false, status: 502, error: "search_failed", message: r.error?.message ?? "검색에 실패했습니다." };
      const sources = pickSources(r.hits, topK);
      if (!sources.length) return { ok: false, status: 404, error: "no_hits", message: `"${question}"과 관련된 기록을 찾지 못했습니다.` };
      const prompt = buildAskPrompt(question, sources, existing?.turns ?? []);
      this.opts.log?.(`질문 (${chain.map((a) => a.title).join(" → ")}, 발췌 ${sources.length}개): ${question}`);
      let produced: { text: string; agent: AgentInfo; rail: RailStop[] };
      try {
        produced = await generateWithFallback(chain, prompt, opts.setting.model, opts.worklogDir, {
          ...this.opts,
          planned: rail,
          onTrail: (stops) => {
            if (!this.running) return;
            this.running.rail = stops;
            const cur = stops.find((s) => s.state === "running" || s.state === "wrote");
            if (cur) this.running.agent = cur.id;
          },
        });
      } catch (err) {
        this.opts.log?.(`질문 실패: ${(err as Error).message}`);
        const failed = err instanceof AgentFailed ? err.rail : this.running?.rail;
        return { ok: false, status: 502, error: "agent_failed", message: (err as Error).message, ...(failed ? { rail: failed } : {}) };
      }
      const now = new Date();
      const conv: Conversation = existing ?? { id: this.store.newId(now), title: clipText(question, 60), createdAt: now.toISOString(), updatedAt: now.toISOString(), turns: [] };
      const result: AskResult = { q: question, answer: produced.text, sources, agent: produced.agent.id, ms: Date.now() - started, at: now.toISOString(), conversationId: conv.id, turn: conv.turns.length, rail: produced.rail };
      conv.turns.push(result);
      conv.updatedAt = now.toISOString();
      try {
        this.store.save(conv);
      } catch (err) {
        this.opts.log?.(`대화 저장 실패: ${(err as Error).message}`);
      }
      this.lastResult = result;
      this.opts.log?.(`답 (${result.ms}ms, ${produced.agent.title}): ${produced.text.slice(0, 120).replace(/\n/g, " ")}`);
      return { ok: true, result };
    } finally {
      this.running = null;
    }
  }
}

export type GenerateOpts = { exec?: Exec; fetchImpl?: typeof fetch; env?: NodeJS.ProcessEnv; timeoutMs?: number };

/**
 * One read-only round trip to the chosen agent: the prompt in, plain text out. Shared by the
 * question mode and the reports (reports.ts). The CLI runs with `cwd` but without tools.
 */
export async function generateText(agent: AgentInfo, prompt: string, model: string, cwd: string, opts: GenerateOpts = {}): Promise<string> {
  if (agent.id === "openrouter") {
    const key = openrouterKey();
    if (!key) throw new Error("OpenRouter 키가 없습니다.");
    const text = await chatText(key, model || DEFAULT_OPENROUTER_MODEL, prompt, opts.fetchImpl, opts.timeoutMs);
    if (!text) throw new Error("모델이 빈 답을 돌려줬습니다.");
    return text;
  }
  const exec = opts.exec ?? execCli;
  // Codex writes its final message to a file; stdout carries its progress log.
  const tmp = agent.id === "codex" ? await mkdtemp(join(tmpdir(), "zv-ask-")) : null;
  const outFile = tmp ? join(tmp, "answer.md") : undefined;
  try {
    const r = await exec(agent.bin!, askCliArgs(agent.id, prompt, { outFile }), cwd, opts.env, opts.timeoutMs);
    let text = r.stdout;
    if (outFile) text = await readFile(outFile, "utf8").catch(() => r.stdout);
    text = cleanAnswer(text);
    const quota = !r.ok ? quotaReason(`${r.stderr}\n${r.stdout}`) : null;
    if (quota) throw new Error(quota);
    if (!r.ok && !text) throw new Error(`${agent.title} 실행 실패: ${(r.stderr || r.stdout).split("\n").slice(-3).join(" / ") || "출력 없음"}`);
    if (!text) throw new Error(`${agent.title}가 답을 돌려주지 않았습니다. ${r.stderr.split("\n").slice(-2).join(" / ")}`.trim());
    return text;
  } finally {
    if (tmp) await rm(tmp, { recursive: true, force: true });
  }
}

/**
 * Tries `agents` in order. A quota error marks that stop and continues; any other failure stops.
 * `planned` is the full rail (including tools that will not be called) so the app can draw it live.
 */
export async function generateWithFallback(agents: AgentInfo[], prompt: string, model: string, cwd: string, opts: GenerateOpts & { planned?: RailStop[]; onTrail?: (rail: RailStop[]) => void } = {}): Promise<{ text: string; agent: AgentInfo; rail: RailStop[] }> {
  let rail = opts.planned ? opts.planned.map((s) => ({ ...s })) : agents.map((a) => ({ id: a.id, title: a.title, metered: a.id === "openrouter", state: "ready" as const }));
  const note = () => opts.onTrail?.(rail.map((s) => ({ ...s })));
  note();
  let last = "답을 쓰지 못했습니다.";
  for (const agent of agents) {
    rail = withStop(rail, agent.id, "running");
    note();
    try {
      const text = await generateText(agent, prompt, model, cwd, opts);
      rail = withStop(rail, agent.id, "wrote");
      note();
      return { text, agent, rail };
    } catch (err) {
      const message = (err as Error).message;
      const quota = quotaReason(message);
      if (quota) {
        rail = withStop(rail, agent.id, "quota", quota);
        last = rail.filter((s) => s.state === "quota").map((s) => `${s.title} 할당량 (${s.reason})`).join(" → ");
        note();
        continue;
      }
      rail = withStop(rail, agent.id, "error", message.replace(/\s+/g, " ").slice(0, 80));
      note();
      throw new AgentFailed(message, rail);
    }
  }
  throw new AgentFailed(`${last}. 넘길 서비스가 없습니다.`, rail);
}
