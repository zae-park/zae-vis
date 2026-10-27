// "질문" (ask): answers a question from the worklog. The search (AutoRAG Lite: BM25 + local vectors)
// picks the passages; an agent the user already has writes the answer from those passages only, with
// [n] citations. The agent is chosen exactly as for the weekly digest (digest.ts): an installed CLI —
// Claude Code, Codex, Gemini — or the saved OpenRouter key. Setting `digest.agent` / `digest.model`
// applies here too, so there is nothing new to configure.
//
// CLIs run with the worklog as cwd but with their tools off (Claude `--tools ""`, Codex
// `--sandbox read-only`, Gemini without `--yolo`), so a question can never change a file.

import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import { delimiter } from "node:path";
import type { SearchBackend, SearchHit } from "./autorag.ts";
import { DEFAULT_OPENROUTER_MODEL, searchDirs, type AgentId, type AgentInfo, type DigestSetting } from "./digest.ts";
import { getKey as openrouterKey } from "./rerank.ts";

export type AskSource = { n: number; path: string; label: string; passage: string };
export type AskResult = { q: string; answer: string; sources: AskSource[]; agent: AgentId; ms: number; at: string };
export type AskError = { status: 400 | 404 | 409 | 502; error: "missing_query" | "no_hits" | "no_agent" | "busy" | "search_failed" | "agent_failed"; message: string };
export type AskOutcome = { ok: true; result: AskResult } | ({ ok: false } & AskError);

export const DEFAULT_TOP_K = 10;
export const MAX_TOP_K = 20;
/** Longer than the 420 chars a search card shows: the model needs the surrounding lines too. */
export const PASSAGE_CHARS = 1000;
const RUN_TIMEOUT_MS = 3 * 60_000;

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

export function buildAskPrompt(q: string, sources: AskSource[]): string {
  const list = sources.map((s) => `[${s.n}] (${s.label}) ${s.path}\n${s.passage}`).join("\n\n");
  return `아래 발췌는 내 작업 기록(worklog)에서 질문과 관련 있어 검색된 문단이다. 이 발췌만 근거로 질문에 한국어로 답한다.

규칙:
- 각 문장 끝에 근거가 된 발췌 번호를 [n] 꼴로 단다. 여러 발췌가 근거면 [1][3]처럼 붙인다.
- 발췌에 없는 내용은 쓰지 않는다. 발췌로 답할 수 없으면 "기록에서 근거를 찾지 못했습니다."라고 쓰고, 가장 가까운 내용이 있으면 그것만 한 문장으로 덧붙인다.
- 파일을 열거나 명령을 실행하지 않는다. 서론·제목·인사 없이 답만 쓴다 (5문장 이내, 필요하면 짧은 목록).

질문: ${q}

발췌:
${list}`;
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

export type Exec = (bin: string, args: string[], cwd: string, env?: NodeJS.ProcessEnv) => Promise<{ ok: boolean; stdout: string; stderr: string }>;

/** Like digest.runCli but keeps stdout (the answer) apart from stderr (progress chatter). */
export const execCli: Exec = (bin, args, cwd, env) =>
  new Promise((res) => {
    const child = spawn(bin, args, { cwd, env: { ...(env ?? process.env), PATH: searchDirs(env).join(delimiter), NO_COLOR: "1" }, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout?.on("data", (c: Buffer) => (stdout = (stdout + c.toString()).slice(-40_000)));
    child.stderr?.on("data", (c: Buffer) => (stderr = (stderr + c.toString()).slice(-10_000)));
    const t = setTimeout(() => {
      child.kill("SIGTERM");
      stderr += "\n[시간 초과]";
    }, RUN_TIMEOUT_MS);
    child.on("error", (e) => {
      clearTimeout(t);
      res({ ok: false, stdout, stderr: e.message });
    });
    child.on("close", (code) => {
      clearTimeout(t);
      res({ ok: code === 0, stdout: stdout.trim(), stderr: stderr.trim() });
    });
  });

export async function chatText(key: string, model: string, prompt: string, fetchImpl: typeof fetch = fetch): Promise<string> {
  const res = await fetchImpl("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: { authorization: `Bearer ${key}`, "content-type": "application/json", "HTTP-Referer": "https://github.com/zae-park/zaevis", "X-Title": "zaevis" },
    body: JSON.stringify({ model, messages: [{ role: "user", content: prompt }], temperature: 0.2 }),
    signal: AbortSignal.timeout(RUN_TIMEOUT_MS),
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

export class AskRunner {
  private running: { q: string; startedAt: string; agent: AgentId } | null = null;
  private lastResult: AskResult | null = null;
  private readonly opts: { exec?: Exec; fetchImpl?: typeof fetch; env?: NodeJS.ProcessEnv; log?: (line: string) => void };

  constructor(opts: { exec?: Exec; fetchImpl?: typeof fetch; env?: NodeJS.ProcessEnv; log?: (line: string) => void } = {}) {
    this.opts = opts;
  }

  status(): { running: { q: string; startedAt: string; agent: AgentId } | null; last: AskResult | null } {
    return { running: this.running, last: this.lastResult };
  }

  /** One question at a time: a second one while an agent is working gets `busy`. */
  async ask(q: string, opts: { search: SearchBackend; agent: AgentInfo | null; setting: Pick<DigestSetting, "model">; worklogDir: string; topK?: number }): Promise<AskOutcome> {
    const question = q.trim();
    if (!question) return { ok: false, status: 400, error: "missing_query", message: "질문을 입력하세요." };
    if (!opts.agent) return { ok: false, status: 409, error: "no_agent", message: NO_AGENT_MESSAGE };
    if (this.running) return { ok: false, status: 409, error: "busy", message: `아직 답을 만드는 중입니다: "${this.running.q.slice(0, 40)}"` };
    const topK = Math.min(Math.max(opts.topK ?? DEFAULT_TOP_K, 1), MAX_TOP_K);
    const started = Date.now();
    this.running = { q: question, startedAt: new Date(started).toISOString(), agent: opts.agent.id };
    try {
      // fetch a few more than needed so weak hits can be dropped
      const r = await opts.search.search(question, Math.min(topK + 5, 50), PASSAGE_CHARS);
      if (!r.ok) return { ok: false, status: 502, error: "search_failed", message: r.error?.message ?? "검색에 실패했습니다." };
      const sources = pickSources(r.hits, topK);
      if (!sources.length) return { ok: false, status: 404, error: "no_hits", message: `"${question}"과 관련된 기록을 찾지 못했습니다.` };
      const prompt = buildAskPrompt(question, sources);
      this.opts.log?.(`질문 (${opts.agent.title}, 발췌 ${sources.length}개): ${question}`);
      let answer: string;
      try {
        answer = await this.answer(opts.agent, prompt, opts.setting.model, opts.worklogDir);
      } catch (err) {
        this.opts.log?.(`질문 실패: ${(err as Error).message}`);
        return { ok: false, status: 502, error: "agent_failed", message: (err as Error).message };
      }
      const result: AskResult = { q: question, answer, sources, agent: opts.agent.id, ms: Date.now() - started, at: new Date().toISOString() };
      this.lastResult = result;
      this.opts.log?.(`답 (${result.ms}ms): ${answer.slice(0, 120).replace(/\n/g, " ")}`);
      return { ok: true, result };
    } finally {
      this.running = null;
    }
  }

  private async answer(agent: AgentInfo, prompt: string, model: string, cwd: string): Promise<string> {
    if (agent.id === "openrouter") {
      const key = openrouterKey();
      if (!key) throw new Error("OpenRouter 키가 없습니다.");
      const text = await chatText(key, model || DEFAULT_OPENROUTER_MODEL, prompt, this.opts.fetchImpl);
      if (!text) throw new Error("모델이 빈 답을 돌려줬습니다.");
      return text;
    }
    const exec = this.opts.exec ?? execCli;
    // Codex writes its final message to a file; stdout carries its progress log.
    const tmp = agent.id === "codex" ? await mkdtemp(join(tmpdir(), "zv-ask-")) : null;
    const outFile = tmp ? join(tmp, "answer.md") : undefined;
    try {
      const r = await exec(agent.bin!, askCliArgs(agent.id, prompt, { outFile }), cwd, this.opts.env);
      let text = r.stdout;
      if (outFile) text = await readFile(outFile, "utf8").catch(() => r.stdout);
      text = cleanAnswer(text);
      if (!r.ok && !text) throw new Error(`${agent.title} 실행 실패: ${(r.stderr || r.stdout).split("\n").slice(-3).join(" / ") || "출력 없음"}`);
      if (!text) throw new Error(`${agent.title}가 답을 돌려주지 않았습니다. ${r.stderr.split("\n").slice(-2).join(" / ")}`.trim());
      return text;
    } finally {
      if (tmp) await rm(tmp, { recursive: true, force: true });
    }
  }
}
