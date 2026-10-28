// "정리" (digest): turns what was collected — sources/*, inbox transcripts and session notes — into log
// lines, project updates and (monthly) a summary, following the worklog README. The work is done by
// whatever the user already has: an installed agent CLI running on their own subscription
// (Claude Code, Codex, Gemini CLI), or, with a saved OpenRouter key, a plain chat model driven by
// this module. Nothing here needs a new account.
//
//   setting  config.json → digest: { agent: "auto" | "claude" | "codex" | "gemini" | "openrouter", model, weekly }
//   state    state.json  → digest: { lastRun, agent, ok, report }
//   log      $ZAEVIS_HOME/digest.log

import { existsSync, mkdirSync, readFileSync, statSync } from "node:fs";
import { appendFile, mkdir, readdir, readFile, rename, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, delimiter, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadState, saveState, stateDir, type AppConfig } from "./config.ts";
import { spawnBin } from "./spawnbin.ts";
import { fallbackCandidates, plannedRail, quotaReason, withStop, type RailStop } from "./rail.ts";
import { getKey as openrouterKey } from "./rerank.ts";
import { diffSnapshot, isEmptyProposal, newProposalId, restoreSnapshot, saveProposal, takeSnapshot } from "./review.ts";
import { Worklog } from "./worklog.ts";

export type AgentId = "claude" | "codex" | "gemini" | "openrouter";
/** `review`: lift the run's changes into a proposal the user approves in the app (default), or apply directly. */
export type DigestSetting = { agent: "auto" | AgentId; model: string; weekly: boolean; review: boolean };

export type AgentInfo = {
  id: AgentId;
  title: string;
  available: boolean;
  /** "2.1.304" for a CLI, "키 저장됨" for OpenRouter, or why it is unavailable. */
  detail: string;
  bin?: string;
  /** Signed in? `false` means installed but it would answer "Not logged in"; `null` = unknown / not applicable (OpenRouter, not installed). */
  loggedIn: boolean | null;
  /** What to do when `loggedIn` is false, e.g. "터미널에서 claude login". */
  loginHint?: string;
};

export type ExecResult = { code: number | null; out: string };
export type DetectOptions = {
  /** Runs a CLI (tests inject this); the default spawns it with a timeout. */
  exec?: (bin: string, args: string[], timeoutMs: number) => Promise<ExecResult>;
  /** Per-binary cache for version and login lookups (default: module-level, LOGIN_CACHE_MS). */
  cache?: Map<string, AgentCacheEntry>;
  now?: () => number;
};
export type AgentCacheEntry = { at: number; version?: string; loggedIn?: boolean | null };

export type DigestRun = { lastRun: string; agent: AgentId; ok: boolean; report: string; proposalId?: string; rail?: RailStop[] };
export type DigestStatus = { running: boolean; startedAt?: string; agent?: AgentId; last: DigestRun | null; nextWeekly: string | null; rail: RailStop[] };

export const DEFAULT_OPENROUTER_MODEL = "anthropic/claude-sonnet-4.5";
const RUN_TIMEOUT_MS = 30 * 60_000;

// ── detection ──────────────────────────────────────────────────────────────────

const CLI: Record<Exclude<AgentId, "openrouter">, { title: string; versionArgs: string[]; loginHint: string }> = {
  claude: { title: "Claude Code", versionArgs: ["--version"], loginHint: "터미널에서 claude login" },
  codex: { title: "Codex CLI", versionArgs: ["--version"], loginHint: "터미널에서 codex login" },
  gemini: { title: "Gemini CLI", versionArgs: ["--version"], loginHint: "터미널에서 gemini를 실행해 로그인하거나 GEMINI_API_KEY 설정" },
};

/** Version and login answers are kept this long: a login check may run the CLI, and status is polled often. */
export const LOGIN_CACHE_MS = 10 * 60_000;
const LOGIN_TIMEOUT_MS = 10_000;
const agentCache = new Map<string, AgentCacheEntry>();

/** PATH plus the places installers put CLIs that a Finder-launched app would not see. */
export function searchDirs(env: NodeJS.ProcessEnv = process.env): string[] {
  const h = env.HOME ?? homedir();
  const extra = ["/opt/homebrew/bin", "/usr/local/bin", join(h, ".local", "bin"), join(h, ".npm-global", "bin"), join(h, ".bun", "bin"), join(h, ".volta", "bin"), join(h, ".codex", "bin")];
  return [...new Set([...(env.PATH ?? "").split(delimiter).filter(Boolean), ...extra])];
}

export function findBin(name: string, env: NodeJS.ProcessEnv = process.env, dirs: string[] = searchDirs(env)): string | null {
  for (const dir of dirs) {
    const p = join(dir, name);
    if (existsSync(p)) return p;
  }
  return null;
}

function probeCli(bin: string, args: string[], timeoutMs: number): Promise<ExecResult> {
  return new Promise((res) => {
    const child = spawnBin(bin, args, { stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    child.stdout?.on("data", (c: Buffer) => (out += c.toString()));
    child.stderr?.on("data", (c: Buffer) => (out += c.toString()));
    const t = setTimeout(() => child.kill("SIGKILL"), timeoutMs);
    child.on("close", (code) => {
      clearTimeout(t);
      res({ code, out });
    });
    child.on("error", () => {
      clearTimeout(t);
      res({ code: null, out });
    });
  });
}

const firstLine = (out: string): string => out.trim().split("\n")[0]?.slice(0, 60) ?? "";

/**
 * Whether a CLI is signed in, without running a real prompt where possible:
 *   claude  `claude auth status` (JSON with `loggedIn`); older CLIs without that command get
 *           `claude -p ok --max-turns 1` and are judged by the "Not logged in" text
 *   codex   ~/.codex/auth.json (or $CODEX_HOME), or OPENAI_API_KEY
 *   gemini  ~/.gemini/oauth_creds.json, or GEMINI_API_KEY / GOOGLE_API_KEY
 * `null` when it could not be told (timeout, unexpected output).
 */
export async function checkLogin(id: Exclude<AgentId, "openrouter">, bin: string, env: NodeJS.ProcessEnv = process.env, exec = probeCli): Promise<boolean | null> {
  const h = env.HOME ?? homedir();
  if (id === "codex") return existsSync(join(env.CODEX_HOME || join(h, ".codex"), "auth.json")) || !!env.OPENAI_API_KEY;
  if (id === "gemini") return existsSync(join(h, ".gemini", "oauth_creds.json")) || !!env.GEMINI_API_KEY || !!env.GOOGLE_API_KEY;
  const st = await exec(bin, ["auth", "status"], LOGIN_TIMEOUT_MS);
  const parsed = parseLoggedIn(st.out);
  if (parsed !== null) return parsed;
  if (/not logged in/i.test(st.out)) return false;
  if (!/unknown command|unknown option|too many arguments|error: unknown/i.test(st.out) && st.code === 0) return null;
  // no `auth status` in this version: the "Not logged in" text of a real (tiny) prompt is the only signal
  const p = await exec(bin, ["-p", "ok", "--max-turns", "1"], LOGIN_TIMEOUT_MS);
  if (/not logged in|please log in|run \/login/i.test(p.out)) return false;
  return p.code === 0 ? true : null;
}

/** `loggedIn` from the JSON of `claude auth status`, tolerating text before or after it. */
export function parseLoggedIn(out: string): boolean | null {
  const i = out.indexOf("{");
  const j = out.lastIndexOf("}");
  if (i < 0 || j <= i) return null;
  try {
    const v = JSON.parse(out.slice(i, j + 1)) as { loggedIn?: unknown };
    return typeof v.loggedIn === "boolean" ? v.loggedIn : null;
  } catch {
    return null;
  }
}

export async function detectAgents(env: NodeJS.ProcessEnv = process.env, hasOpenrouterKey = openrouterKey() !== null, dirs: string[] = searchDirs(env), opts: DetectOptions = {}): Promise<AgentInfo[]> {
  const exec = opts.exec ?? probeCli;
  const cache = opts.cache ?? agentCache;
  const now = opts.now ?? Date.now;
  const out: AgentInfo[] = [];
  for (const id of ["claude", "codex", "gemini"] as const) {
    const bin = findBin(id, env, dirs);
    if (!bin) {
      out.push({ id, title: CLI[id].title, available: false, detail: "설치되지 않음", loggedIn: null });
      continue;
    }
    let entry = cache.get(bin);
    if (!entry || now() - entry.at > LOGIN_CACHE_MS) {
      const v = firstLine((await exec(bin, CLI[id].versionArgs, 8000)).out);
      entry = { at: now(), version: v, loggedIn: await checkLogin(id, bin, env, exec) };
      cache.set(bin, entry);
    }
    out.push({ id, title: CLI[id].title, available: true, detail: entry.version || "설치됨", bin, loggedIn: entry.loggedIn ?? null, loginHint: CLI[id].loginHint });
  }
  out.push({ id: "openrouter", title: "OpenRouter API", available: hasOpenrouterKey, detail: hasOpenrouterKey ? "키 저장됨 (설정 → 검색 결과 재정렬)" : "키 없음 — 설정 → 검색 결과 재정렬에서 저장", loggedIn: null });
  return out;
}

/** Installed and not known to be signed out. */
export const usable = (a: AgentInfo): boolean => a.available && a.loggedIn !== false;

/** Why nothing can run right now — names a CLI that only needs a login, when there is one. */
export function noAgentReason(agents: AgentInfo[] = []): string {
  const base = "쓸 수 있는 에이전트가 없습니다. Claude Code·Codex·Gemini CLI 중 하나를 설치하거나 설정에서 OpenRouter 키를 저장하세요.";
  const out = agents.filter((a) => a.available && a.loggedIn === false).map((a) => `${a.title}는 설치돼 있지만 로그인되지 않았습니다 (${a.loginHint ?? "로그인 필요"}).`);
  return out.length ? `${out.join(" ")} ${base}` : base;
}

/** "auto" = the first usable in the order above (a subscription CLI before a pay-per-use API); a signed-out CLI is skipped. */
export function pickAgent(setting: DigestSetting, agents: AgentInfo[]): AgentInfo | null {
  if (setting.agent !== "auto") return agents.find((a) => a.id === setting.agent && usable(a)) ?? null;
  return agents.find(usable) ?? null;
}

// ── the task ───────────────────────────────────────────────────────────────────

function kitDir(): string {
  return resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "kit");
}

/** The weekly prompt (kit/claude/weekly-task-prompt.md) filled in for this worklog. */
export function buildPrompt(cfg: Pick<AppConfig, "worklogDir" | "reposRoot">): string {
  const file = join(kitDir(), "claude", "weekly-task-prompt.md");
  let p = existsSync(file) ? readFileSync(file, "utf8") : `${cfg.worklogDir}/README.md 를 읽고 "주간 정리" 절차를 따른다.`;
  p = p.replace(/\{\{WORKLOG_DIR\}\}/g, cfg.worklogDir).replace(/\{\{REPOS_ROOT\}\}/g, cfg.reposRoot);
  return p + `\n\n추가 규칙: ${cfg.worklogDir} 폴더 밖의 파일은 읽지도 쓰지도 않는다. 질문하지 말고 끝까지 진행한 뒤 보고만 한다.`;
}

export function isFirstMonday(d = new Date()): boolean {
  return d.getDay() === 1 && d.getDate() <= 7;
}

export function lastWeeklyDate(worklogDir: string): string | null {
  try {
    return /last_weekly:\s*(\d{4}-\d{2}-\d{2})/.exec(readFileSync(join(worklogDir, ".state.md"), "utf8"))?.[1] ?? null;
  } catch {
    return null;
  }
}

/** The weekly run is due on Mondays when the last one is more than 6 days old. */
export function weeklyDue(setting: DigestSetting, worklogDir: string, now = new Date()): boolean {
  if (!setting.weekly || now.getDay() !== 1) return false;
  const last = lastWeeklyDate(worklogDir);
  if (!last) return true;
  return now.getTime() - new Date(last).getTime() > 6 * 86_400_000;
}

export function nextMonday(now = new Date()): string {
  const d = new Date(now);
  d.setDate(d.getDate() + ((8 - d.getDay()) % 7 || 7));
  return d.toISOString().slice(0, 10);
}

// ── running a CLI agent ────────────────────────────────────────────────────────

export function cliArgs(agent: Exclude<AgentId, "openrouter">, prompt: string): string[] {
  switch (agent) {
    case "claude":
      // edits inside the worklog auto-accepted; shell limited to what the procedure needs
      return ["-p", prompt, "--output-format", "text", "--permission-mode", "acceptEdits", "--max-turns", "80",
        "--allowedTools", "Read", "Edit", "Write", "Glob", "Grep", "Bash(git log:*)", "Bash(mv:*)", "Bash(mkdir:*)", "Bash(ls:*)", "Bash(cat:*)", "Bash(date:*)"];
    case "codex":
      return ["exec", "--full-auto", prompt];
    case "gemini":
      return ["-p", prompt, "--yolo"];
  }
}

type RunOpts = { env?: NodeJS.ProcessEnv; timeoutMs?: number; log?: (line: string) => void };

export function runCli(bin: string, args: string[], cwd: string, opts: RunOpts = {}): Promise<{ ok: boolean; output: string }> {
  return new Promise((res) => {
    const child = spawnBin(bin, args, { cwd, env: { ...(opts.env ?? process.env), PATH: searchDirs(opts.env).join(delimiter), NO_COLOR: "1" }, stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    const take = (c: Buffer) => {
      const s = c.toString();
      out = (out + s).slice(-20_000);
      for (const line of s.split("\n")) if (line.trim()) opts.log?.(line);
    };
    child.stdout?.on("data", take);
    child.stderr?.on("data", take);
    const t = setTimeout(() => {
      child.kill("SIGTERM");
      out += "\n[시간 초과]";
    }, opts.timeoutMs ?? RUN_TIMEOUT_MS);
    child.on("error", (e) => {
      clearTimeout(t);
      res({ ok: false, output: `${e.message}` });
    });
    child.on("close", (code) => {
      clearTimeout(t);
      res({ ok: code === 0, output: out.trim() });
    });
  });
}

// ── running through OpenRouter (no agent: this module gathers inputs and applies the answer) ──

const RULES = `너는 개인 작업 기록(worklog)을 정리하는 비서다. 입력(수집 원본·전사본·세션 노트)을 읽고 JSON 하나만 출력한다.
규칙: 한국어. 원본을 그대로 옮기지 않고 같은 날 같은 일은 의미 단위로 묶어 한 줄, 왜 했는지가 보이게. 셸 명령 이력은 다른 기록의 맥락 보충에만 쓴다.
이미 있는 로그 줄과 같은 내용은 넣지 않는다. 로그·원본에 없는 사실은 쓰지 않는다. 각 줄의 src 는 근거 원본(파일명이나 "git <저장소> <해시7>", "claude-code YYYY-MM-DD", "agent-sessions YYYY-MM-DD").
tags 는 done / decision / blocked / learned 중에서만. projects 의 slug 는 기존 프로젝트 slug 를 우선 쓰고, 분명히 새 프로젝트일 때만 새 slug(영문 소문자·숫자·하이픈)를 만든다.
출력 형식:
{"logLines":[{"date":"YYYY-MM-DD","projects":["slug"],"tags":["done"],"text":"…","src":"…"}],
 "projects":[{"slug":"…","title":"…","currentState":"…","decisions":["…"],"openIssues":["…"]}],
 "processed":["inbox/transcripts/파일.txt"],
 "monthlySummary": null 또는 "# YYYY-MM 작업 정리\\n## 한 줄 요약\\n…\\n## 프로젝트별\\n…\\n## 막힌 것 / 다음 달로 넘어간 것\\n…\\n## 배운 것\\n…"}`;

type Plan = {
  logLines?: Array<{ date?: string; projects?: string[]; tags?: string[]; text?: string; src?: string }>;
  projects?: Array<{ slug?: string; title?: string; currentState?: string; decisions?: string[]; openIssues?: string[] }>;
  processed?: string[];
  monthlySummary?: string | null;
};

async function listFiles(dir: string): Promise<string[]> {
  try {
    return (await readdir(dir)).filter((n) => !n.startsWith(".")).sort().map((n) => join(dir, n));
  } catch {
    return [];
  }
}

/** Everything the weekly step reads, capped so the request stays within a model's context. */
export async function gatherInputs(worklogDir: string, since: string | null, capChars = 160_000): Promise<{ files: string[]; text: string }> {
  const picked: string[] = [];
  const sourcesRoot = join(worklogDir, "sources");
  for (const src of await listFiles(sourcesRoot)) {
    for (const f of await listFiles(src)) {
      const day = /(\d{4}-\d{2}-\d{2})\.md$/.exec(f)?.[1];
      if (day && (!since || day > since)) picked.push(f);
    }
  }
  for (const sub of ["transcripts", "claude-sessions"]) picked.push(...(await listFiles(join(worklogDir, "inbox", sub))));
  let text = "";
  const files: string[] = [];
  for (const f of picked) {
    if (!statSync(f).isFile()) continue;
    const rel = f.slice(worklogDir.length + 1).replaceAll("\\", "/");
    let body = await readFile(f, "utf8");
    if (body.length > 12_000) body = body.slice(0, 12_000) + "\n…(잘림)";
    const chunk = `\n\n===== ${rel} =====\n${body}`;
    if (text.length + chunk.length > capChars) break;
    text += chunk;
    files.push(rel);
  }
  return { files, text };
}

export async function chatJson(key: string, model: string, system: string, user: string, fetchImpl: typeof fetch = fetch): Promise<Plan> {
  const res = await fetchImpl("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: { authorization: `Bearer ${key}`, "content-type": "application/json", "HTTP-Referer": "https://github.com/zae-park/zaevis", "X-Title": "zaevis" },
    body: JSON.stringify({ model, messages: [{ role: "system", content: system }, { role: "user", content: user }], response_format: { type: "json_object" }, temperature: 0.2 }),
    signal: AbortSignal.timeout(10 * 60_000),
  });
  if (!res.ok) throw new Error(`OpenRouter HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const body = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> };
  const content = body.choices?.[0]?.message?.content ?? "";
  const json = content.slice(content.indexOf("{"), content.lastIndexOf("}") + 1);
  return JSON.parse(json) as Plan;
}

/** Replaces the body under `## heading` (keeps the rest). Appends the section when missing. */
export function setSection(markdown: string, heading: string, body: string): string {
  const lines = markdown.split("\n");
  const start = lines.findIndex((l) => l.trim() === `## ${heading}`);
  const block = [`## ${heading}`, "", body.trim(), ""];
  if (start < 0) return markdown.replace(/\s*$/, "\n\n") + block.join("\n");
  let end = start + 1;
  while (end < lines.length && !/^##\s/.test(lines[end])) end++;
  return [...lines.slice(0, start), ...block, ...lines.slice(end)].join("\n");
}

export async function applyPlan(worklogDir: string, plan: Plan, today = new Date()): Promise<{ lines: number; projects: string[]; processed: number; summary: string | null }> {
  const wl = new Worklog(worklogDir);
  let lines = 0;
  for (const l of plan.logLines ?? []) {
    const text = (l.text ?? "").trim();
    if (!text) continue;
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(l.date ?? "");
    const date = m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : today;
    const src = (l.src ?? "").trim();
    await wl.appendLog({ text: src ? `${text} (src: ${src})` : text, tags: l.tags ?? [], projects: l.projects ?? [], date });
    lines++;
  }
  const touched: string[] = [];
  for (const p of plan.projects ?? []) {
    const slug = (p.slug ?? "").trim().toLowerCase();
    if (!/^[a-z0-9][a-z0-9._-]*$/.test(slug)) continue;
    const file = join(worklogDir, "projects", `${slug}.md`);
    let md: string;
    if (existsSync(file)) md = await readFile(file, "utf8");
    else {
      const tpl = join(kitDir(), "templates", "worklog", "projects", "_template.md");
      md = (existsSync(tpl) ? readFileSync(tpl, "utf8") : "---\nrepos: []\nstatus: 진행 중\n---\n# 프로젝트 이름\n\n## 현재 상태\n\n## 주요 결정\n\n## 열린 문제\n\n## 링크\n").replace("# 프로젝트 이름", `# ${p.title?.trim() || slug}`);
    }
    if (p.currentState?.trim()) md = setSection(md, "현재 상태", p.currentState);
    if (p.decisions?.length) md = setSection(md, "주요 결정", p.decisions.map((d) => `- ${d}`).join("\n"));
    if (p.openIssues?.length) md = setSection(md, "열린 문제", p.openIssues.map((d) => `- ${d}`).join("\n"));
    await mkdir(dirname(file), { recursive: true });
    await writeFile(file, md.endsWith("\n") ? md : md + "\n");
    touched.push(slug);
  }
  let processed = 0;
  for (const rel of plan.processed ?? []) {
    const m = /^inbox\/(transcripts|claude-sessions)\/([^/]+)$/.exec(rel);
    if (!m) continue;
    const from = join(worklogDir, "inbox", m[1], m[2]);
    if (!existsSync(from)) continue;
    const toDir = join(worklogDir, "processed", m[1]);
    await mkdir(toDir, { recursive: true });
    await rename(from, join(toDir, m[2]));
    processed++;
  }
  let summary: string | null = null;
  if (plan.monthlySummary && plan.monthlySummary.trim().startsWith("#")) {
    const prev = new Date(today.getFullYear(), today.getMonth() - 1, 1);
    const name = `${prev.getFullYear()}-${String(prev.getMonth() + 1).padStart(2, "0")}.md`;
    const file = join(worklogDir, "summaries", name);
    if (!existsSync(file)) {
      await mkdir(dirname(file), { recursive: true });
      await writeFile(file, plan.monthlySummary.trim() + "\n");
      summary = name;
    }
  }
  await writeFile(join(worklogDir, ".state.md"), `last_weekly: ${today.toISOString().slice(0, 10)}\n`);
  return { lines, projects: touched, processed, summary };
}

export async function runOpenRouter(cfg: Pick<AppConfig, "worklogDir">, model: string, opts: { fetchImpl?: typeof fetch; log?: (l: string) => void; today?: Date } = {}): Promise<{ ok: boolean; output: string }> {
  const key = openrouterKey();
  if (!key) return { ok: false, output: "OpenRouter 키가 없습니다." };
  const since = lastWeeklyDate(cfg.worklogDir);
  const inputs = await gatherInputs(cfg.worklogDir, since);
  if (!inputs.files.length) return { ok: true, output: `정리할 새 입력이 없습니다 (마지막 정리: ${since ?? "없음"}).` };
  opts.log?.(`입력 ${inputs.files.length}개 파일, ${inputs.text.length}자 → ${model}`);
  const wl = new Worklog(cfg.worklogDir);
  const projects = (await wl.projects()).map((p) => `- ${p.slug}: ${p.title} (${p.status}) ${p.currentState.slice(0, 120)}`).join("\n") || "(없음)";
  const month = `${(opts.today ?? new Date()).getFullYear()}-${String((opts.today ?? new Date()).getMonth() + 1).padStart(2, "0")}`;
  const recent = ((await wl.log(month)) ?? []).slice(-60).map((e) => `- ${e.date} ${e.text}`).join("\n") || "(없음)";
  const monthly = isFirstMonday(opts.today) ? "오늘은 이 달의 첫 월요일이다. 지난달 로그와 프로젝트로 monthlySummary 초안도 쓴다." : "monthlySummary 는 null 로 둔다.";
  const user = `오늘: ${(opts.today ?? new Date()).toISOString().slice(0, 10)} · 마지막 정리: ${since ?? "없음"}\n${monthly}\n\n기존 프로젝트:\n${projects}\n\n이 달의 기존 로그 줄(중복 금지):\n${recent}\n\n입력:${inputs.text}`;
  const plan = await chatJson(key, model, RULES, user, opts.fetchImpl);
  const r = await applyPlan(cfg.worklogDir, plan, opts.today);
  return { ok: true, output: `로그 ${r.lines}줄 추가 · 프로젝트 ${r.projects.length}개 갱신(${r.projects.join(", ") || "-"}) · inbox ${r.processed}개 처리${r.summary ? ` · 월간 초안 ${r.summary}` : ""}` };
}

// ── the runner the server and the daily job share ──────────────────────────────

export class DigestRunner {
  private running: { startedAt: string; agent: AgentId; promise: Promise<DigestRun> } | null = null;
  private rail: RailStop[] = [];
  private readonly opts: { env?: NodeJS.ProcessEnv; fetchImpl?: typeof fetch; notify?: (title: string, body: string) => void };

  constructor(opts: { env?: NodeJS.ProcessEnv; fetchImpl?: typeof fetch; notify?: (title: string, body: string) => void } = {}) {
    this.opts = opts;
  }

  status(setting: DigestSetting, worklogDir: string): DigestStatus {
    const last = (loadState() as { digest?: DigestRun }).digest ?? null;
    return {
      running: this.running !== null,
      ...(this.running ? { startedAt: this.running.startedAt, agent: this.running.agent } : {}),
      last,
      nextWeekly: setting.weekly ? nextMonday() : null,
      rail: this.running ? this.rail : [],
    };
  }

  /**
   * Starts a run unless one is in progress. `chain` is the detected agent list: in auto mode a quota
   * error before any file change tries the next usable agent. Once the worklog has changed, the run
   * stops on that agent. Without `chain` (and whenever the setting is pinned) only `agent` runs.
   */
  run(cfg: AppConfig, setting: DigestSetting, agent: AgentInfo, chain?: AgentInfo[]): Promise<DigestRun> {
    if (this.running) return this.running.promise;
    const startedAt = new Date().toISOString();
    const candidates = chain && setting.agent === "auto" ? fallbackCandidates(setting, chain) : [];
    const list = candidates.length ? candidates : [agent];
    this.rail = chain ? plannedRail(setting, chain) : plannedRail({ agent: agent.id }, [agent]);
    const logFile = join(stateDir(), "digest.log");
    mkdirSync(stateDir(), { recursive: true });
    const log = (line: string) => {
      void appendFile(logFile, `[${new Date().toLocaleString("sv-SE")}] ${line}\n`).catch(() => {});
    };
    const holder: { startedAt: string; agent: AgentId; promise: Promise<DigestRun> } = { startedAt, agent: list[0].id, promise: undefined as never };
    const promise = (async (): Promise<DigestRun> => {
      let run: DigestRun | undefined;
      for (let i = 0; i < list.length; i++) {
        const current = list[i];
        const more = setting.agent === "auto" && i < list.length - 1;
        holder.agent = current.id;
        this.rail = withStop(this.rail, current.id, "running");
        log(`정리 시작 (${current.title}${setting.review ? ", 검토 후 적용" : ""})`);
        // A snapshot when we might fall through, and always in review mode (the proposal is the diff).
        const before = setting.review || more ? await takeSnapshot(cfg.worklogDir) : null;
        let r: { ok: boolean; output: string };
        try {
          if (current.id === "openrouter") r = await runOpenRouter(cfg, setting.model || DEFAULT_OPENROUTER_MODEL, { fetchImpl: this.opts.fetchImpl, log });
          else r = await runCli(current.bin!, cliArgs(current.id, buildPrompt(cfg)), cfg.worklogDir, { env: this.opts.env, log });
        } catch (err) {
          r = { ok: false, output: (err as Error).message };
        }
        const quota = !r.ok ? quotaReason(r.output) : null;
        if (before && quota && more) {
          const diff = await diffSnapshot(cfg.worklogDir, before);
          const wrote = !isEmptyProposal(diff) || diff.removedLines.length > 0 || diff.stateAfter != null;
          if (!wrote) {
            await restoreSnapshot(cfg.worklogDir, before);
            this.rail = withStop(this.rail, current.id, "quota", quota);
            log(`${current.title} 할당량으로 건너뜀 (${quota})`);
            continue;
          }
        }
        this.rail = withStop(this.rail, current.id, r.ok ? "wrote" : quota ? "quota" : "error", quota ?? (!r.ok ? r.output.split("\n").filter((l) => l.trim()).at(-1)?.slice(0, 80) : undefined));
        let proposalId: string | undefined;
        if (before && setting.review) {
          const diff = await diffSnapshot(cfg.worklogDir, before);
          await restoreSnapshot(cfg.worklogDir, before);
          if (!isEmptyProposal(diff)) {
            proposalId = newProposalId();
            await saveProposal({ id: proposalId, createdAt: new Date().toISOString(), agent: current.id, report: r.output.slice(-4000), status: "pending", ...diff });
            const summary = `검토 대기: 로그 ${diff.logLines.length}줄 · 프로젝트 ${diff.projects.length}개 · inbox ${diff.processed.length}개${diff.summaries.length ? ` · 월간 초안 ${diff.summaries.length}` : ""}${diff.removedLines.length ? ` · 지운 줄 ${diff.removedLines.length}(검토 필요)` : ""}`;
            log(summary);
            r = { ok: r.ok, output: `${summary}\n\n${r.output}` };
          } else if (r.ok) {
            r = { ok: true, output: `바뀐 것이 없습니다.\n\n${r.output}` };
          }
        }
        log(`정리 ${r.ok ? "완료" : "실패"}: ${r.output.split("\n").slice(-3).join(" / ")}`);
        const skipped = this.rail.filter((s) => s.state === "quota").map((s) => s.title);
        run = { lastRun: new Date().toISOString(), agent: current.id, ok: r.ok, report: r.output.slice(-4000), rail: this.rail.map((s) => ({ ...s })), ...(proposalId ? { proposalId } : {}) };
        this.opts.notify?.(
          proposalId ? "정리 제안이 준비됐습니다" : r.ok ? "정리 완료" : "정리 실패",
          skipped.length ? `${skipped.join(", ")} 할당량 → ${current.title}. ${proposalId ? "앱에서 검토하세요." : ""}`.trim() : proposalId ? "앱의 로그 탭이나 설정 → 정리에서 검토하고 적용하세요." : r.output.split("\n").find((l) => l.trim()) ?? "",
        );
        break;
      }
      const finished = run ?? { lastRun: new Date().toISOString(), agent: list[0].id, ok: false, report: "넘길 서비스가 없습니다.", rail: this.rail };
      const state = loadState() as Record<string, unknown>;
      state.digest = finished;
      saveState(state as never);
      return finished;
    })().finally(() => {
      this.running = null;
      this.rail = [];
    });
    holder.promise = promise;
    this.running = holder;
    return promise;
  }
}
