// Terminal client for the zaevis server. Used by `zaevis run cli`, `zaevis search`, `zaevis log`, …
//
//   node src/cli.ts repl
//   node src/cli.ts search <query…> | log [YYYY-MM] | projects | project <slug>
//                   summary [YYYY-MM] | index | refresh [--force] | health

import { existsSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline/promises";
import { stdin, stdout } from "node:process";
import { fileURLToPath } from "node:url";
import { copyFile, mkdir } from "node:fs/promises";
import { basename, extname } from "node:path";
import { loadConfig, loadSources, saveSourceSettings } from "./config.ts";
import { installSchedule, removeSchedule, scheduleStatus } from "./schedule.ts";
import { listSources } from "./sources/index.ts";
import { AUDIO_EXT, TEXT_EXT, transcribeFile, whisperxBin } from "./transcribe.ts";
import { freePath, safeStem } from "./worklog.ts";

// ── colours ────────────────────────────────────────────────────────────────
const useColor = stdout.isTTY && !process.env.NO_COLOR;
const paint = (code: string) => (s: string) => (useColor ? `\x1b[${code}m${s}\x1b[0m` : s);
export const c = {
  bold: paint("1"),
  dim: paint("2"),
  red: paint("31"),
  green: paint("32"),
  yellow: paint("33"),
  blue: paint("34"),
  magenta: paint("35"),
  cyan: paint("36"),
};

const TAG_COLOR: Record<string, (s: string) => string> = {
  done: c.green,
  decision: c.blue,
  blocked: c.red,
  learned: c.yellow,
};
const TAG_LABEL: Record<string, string> = { done: "완료", decision: "결정", blocked: "막힘", learned: "배움" };

// ── API ────────────────────────────────────────────────────────────────────
export function baseUrl(): string {
  if (process.env.ZAEVIS_URL) return process.env.ZAEVIS_URL.replace(/\/$/, "");
  let port = Number(process.env.ZAEVIS_PORT) || 0;
  const cfg = join(process.env.ZAEVIS_HOME ?? join(homedir(), ".zaevis"), "config.json");
  if (!port && existsSync(cfg)) {
    try {
      port = Number(JSON.parse(readFileSync(cfg, "utf8")).port) || 0;
    } catch {
      /* ignore malformed config */
    }
  }
  return `http://127.0.0.1:${port || 4710}`;
}

type J = Record<string, any>;

export class Api {
  readonly base: string;
  constructor(base: string) {
    this.base = base;
  }
  async get(path: string): Promise<J> {
    const res = await fetch(this.base + "/api" + path);
    const body = (await res.json().catch(() => ({}))) as J;
    if (res.status === 404) throw new CliError("찾을 수 없습니다");
    if (!res.ok) throw new CliError(body.message ?? `요청 실패 (${res.status})`);
    return body;
  }
  async post(path: string, body: unknown): Promise<J> {
    const res = await fetch(this.base + "/api" + path, {
      method: "POST",
      headers: { "content-type": "application/json", "x-zaevis": "1" },
      body: JSON.stringify(body),
    });
    return (await res.json().catch(() => ({}))) as J;
  }
}

export class CliError extends Error {}

// ── formatting (pure, tested) ────────────────────────────────────────────────
const wrapIndent = (text: string, indent: string) => text.split("\n").map((l) => indent + l).join("\n");

export function formatHits(r: J): string {
  if (r.ok === false) {
    const msg = r.error?.code === "index-not-ready" ? "아직 색인이 없습니다. `zaevis index --refresh`로 만드세요." : (r.error?.message ?? "검색 실패");
    return c.yellow(msg);
  }
  const hits = (r.hits ?? []) as J[];
  if (!hits.length) return c.dim(`"${r.query}"에 대한 결과가 없습니다.`);
  return hits
    .map((h) => {
      const head = `${c.bold(c.cyan(`[${h.number}]`))} ${c.bold(h.title ?? "")}  ${c.dim(h.path ?? "")}`;
      const snippet = String(h.snippet ?? "").replace(/\s+/g, " ").trim();
      return snippet ? `${head}\n${wrapIndent(snippet.length > 280 ? snippet.slice(0, 280) + "…" : snippet, "    ")}` : head;
    })
    .join("\n\n");
}

export function formatLog(month: string, entries: J[]): string {
  if (!entries.length) return c.dim(`${month}: 로그가 없습니다.`);
  const lines = entries.map((e) => {
    const tags = (e.tags as string[]).map((t) => (TAG_COLOR[t] ?? c.magenta)(TAG_LABEL[t] ?? `#${t}`)).join(" ");
    const projects = (e.projects as string[]).map((p) => c.cyan(p)).join(" ");
    const src = e.source ? c.dim(`  ← ${e.source}`) : "";
    return `${c.dim(e.date)}  ${[tags, projects].filter(Boolean).join(" ")}  ${e.text}${src}`;
  });
  return `${c.bold(month)}\n${lines.join("\n")}`;
}

export function formatProjects(projects: J[]): string {
  if (!projects.length) return c.dim("프로젝트가 없습니다.");
  return projects
    .map((p) => {
      const status = p.status ? c.dim(` [${p.status}]`) : "";
      const state = p.currentState ? `\n    ${String(p.currentState).replace(/\s+/g, " ")}` : "";
      return `${c.bold(p.slug)}  ${p.title}${status}${state}`;
    })
    .join("\n");
}

export function formatIndex(s: J): string {
  const a = (s.autorag ?? {}) as J;
  const state = s.refreshing || a.inFlight ? c.yellow("색인 중…") : a.state === "failed" ? c.red("실패") : String(a.state ?? "알 수 없음");
  const out = [`상태: ${state}`, `최신: ${a.stale ? c.yellow("갱신 필요") : c.green("최신")}`];
  const err = s.lastRefresh?.ok === false ? s.lastRefresh.error : a.lastError;
  if (err) out.push(`오류: ${c.red(String(err))}`);
  const diags = ((a.diagnostics ?? []) as J[]).map((d) => String(d.message ?? "")).filter(Boolean);
  for (const m of diags.slice(0, 3)) out.push(c.dim(`· ${m}`));
  if (diags.length > 3) out.push(c.dim(`· 외 ${diags.length - 3}건`));
  return out.join("\n");
}

/** `#decision [[roas]] 매핑을 수동으로` → { tags, projects, text } */
export function parseAdd(args: string[]): { text: string; tags: string[]; projects: string[] } {
  const tags: string[] = [];
  const projects: string[] = [];
  const words: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if ((a === "-t" || a === "--tag") && args[i + 1]) tags.push(args[++i].replace(/^#/, ""));
    else if ((a === "-p" || a === "--project") && args[i + 1]) projects.push(args[++i]);
    else words.push(a);
  }
  const rest: string[] = [];
  for (const w of words.join(" ").split(/\s+/)) {
    const tag = /^#([\p{L}\p{N}_-]+)$/u.exec(w);
    const link = /^\[\[([^\]]+)\]\]$/.exec(w);
    if (tag) tags.push(tag[1]);
    else if (link) projects.push(link[1]);
    else if (w) rest.push(w);
  }
  return { text: rest.join(" "), tags, projects };
}

export function formatSources(list: Array<Record<string, any>>): string {
  return list
    .map((s) => {
      const dot = !s.enabled ? c.dim("○") : s.lastOk === false ? c.red("●") : c.green("●");
      const when = s.lastRun ? c.dim(new Date(s.lastRun).toLocaleString("sv-SE").slice(0, 16)) : c.dim("수집 전");
      const tail = s.lastOk === false ? c.red(` ${s.lastError}`) : s.lastNote ? c.dim(` ${s.lastNote}`) : "";
      return `${dot} ${c.bold(s.name.padEnd(14))} ${when}${tail}`;
    })
    .join("\n");
}

// Commands that work on local files directly (no server needed).
export async function runLocal(cmd: string, args: string[]): Promise<string | null> {
  const cfg = loadConfig();
  switch (cmd) {
    case "sources": {
      const [action, name] = args;
      if ((action === "on" || action === "off") && name) {
        saveSourceSettings(name, { enabled: action === "on" });
        return `${name}: ${action === "on" ? "켬" : "끔"}`;
      }
      return formatSources(listSources(cfg) as Array<Record<string, any>>);
    }
    case "schedule": {
      const action = args[0] ?? "status";
      const st = action === "install" ? await installSchedule(args[1] ?? cfg.dailyAt) : action === "remove" ? await removeSchedule() : await scheduleStatus();
      if (!st.supported) return c.yellow(`macOS가 아니라 launchd를 쓸 수 없습니다. ${st.hint ?? ""}`);
      if (!st.installed) return `예약 없음. 'zaevis schedule install' 로 매일 ${cfg.dailyAt}에 수집·색인합니다.`;
      return `${st.loaded ? c.green("●") : c.yellow("●")} 매일 ${st.dailyAt} 수집·색인 ${st.loaded ? "" : "(등록됐지만 아직 로드되지 않음)"}\n${c.dim(st.plist)}`;
    }
    case "ingest": {
      if (!args.length) throw new CliError("파일을 지정하세요: zaevis ingest <전사본.txt | 녹음.m4a> …");
      const ts = loadSources(cfg).transcripts ?? { enabled: true };
      const out: string[] = [];
      for (const f of args) {
        const ext = extname(f).toLowerCase();
        if (TEXT_EXT.has(ext)) {
          const dir = join(cfg.worklogDir, "inbox", "transcripts");
          await mkdir(dir, { recursive: true });
          const dest = freePath(dir, safeStem(basename(f)), ext);
          await copyFile(f, dest);
          out.push(`${c.green("✓")} ${basename(dest)}`);
        } else if (AUDIO_EXT.has(ext)) {
          if (!whisperxBin(ts.whisperxBin as string | undefined)) throw new CliError("whisperX가 없습니다: zaevis ext install whisperx");
          console.log(c.dim(`전사 중… ${basename(f)} (길이에 따라 수 분)`));
          const audioDir = String(ts.audioDir ?? join(cfg.worklogDir, "inbox", "audio"));
          await mkdir(audioDir, { recursive: true });
          const staged = freePath(audioDir, safeStem(basename(f)), ext);
          await copyFile(f, staged); // the original stays where it was
          const dest = await transcribeFile(staged, cfg.worklogDir, { language: String(ts.language ?? "ko"), model: String(ts.model ?? "large-v3-turbo") });
          out.push(`${c.green("✓")} ${basename(dest)}`);
        } else {
          out.push(c.yellow(`건너뜀 (지원하지 않는 형식): ${f}`));
        }
      }
      return out.join("\n") + c.dim("\n검색에 잡히려면 다음 색인 후입니다 (지금 하려면 zaevis index --refresh).");
    }
    default:
      return null;
  }
}

// ── commands ─────────────────────────────────────────────────────────────────
async function latest(api: Api, kind: "logs" | "summaries"): Promise<string> {
  const months = ((await api.get(`/${kind}`)).months ?? []) as string[];
  if (!months.length) throw new CliError(kind === "logs" ? "로그가 아직 없습니다." : "월간 정리가 아직 없습니다.");
  return months[0];
}

export async function run(api: Api, cmd: string, args: string[]): Promise<string> {
  switch (cmd) {
    case "search":
    case "s": {
      const q = args.join(" ").trim();
      if (!q) throw new CliError("검색어를 입력하세요: zaevis search <검색어>");
      return formatHits(await api.get(`/search?q=${encodeURIComponent(q)}&topK=10`));
    }
    case "log":
    case "l": {
      const month = args[0] ?? (await latest(api, "logs"));
      return formatLog(month, ((await api.get(`/logs/${encodeURIComponent(month)}`)).entries ?? []) as J[]);
    }
    case "projects":
    case "p":
      return formatProjects(((await api.get("/projects")).projects ?? []) as J[]);
    case "project": {
      if (!args[0]) throw new CliError("프로젝트 slug를 입력하세요: zaevis project <slug>");
      return String((await api.get(`/projects/${encodeURIComponent(args[0])}`)).markdown ?? "");
    }
    case "summary": {
      const month = args[0] ?? (await latest(api, "summaries"));
      return String((await api.get(`/summaries/${encodeURIComponent(month)}`)).markdown ?? "");
    }
    case "index":
      if (args.includes("--refresh") || args.includes("--force")) {
        await api.post("/index", { force: args.includes("--force") });
        return "색인 갱신을 시작했습니다. `zaevis index`로 진행 상태를 확인하세요.";
      }
      return formatIndex(await api.get("/index"));
    case "add": {
      const { text, tags, projects } = parseAdd(args);
      if (!text) throw new CliError('내용을 입력하세요: zaevis add "#decision [[프로젝트]] 무엇을, 왜"');
      const r = await api.post("/logs", { text, tags, projects });
      if (r.error) throw new CliError(r.message ?? r.error);
      return `${c.green("✓")} log/${r.month}.md\n${r.line}`;
    }
    case "inbox": {
      const r = await api.get("/inbox");
      const sec = (title: string, files: J[]) => `${c.bold(title)} ${c.dim(`(${files.length})`)}${files.slice(0, 10).map((f) => `\n  ${f.name}`).join("")}`;
      const jobs = ((r.jobs ?? []) as J[]).map((j) => `\n  ${j.state === "failed" ? c.red(j.state) : j.state} ${j.file}${j.error ? c.dim(" " + j.error) : ""}`).join("");
      return [sec("전사본", r.transcripts ?? []), sec("세션 노트", r.sessions ?? []), sec("전사 대기 녹음", r.audio ?? []), jobs ? c.bold("전사 작업") + jobs : ""].filter(Boolean).join("\n");
    }
    case "health": {
      const h = await api.get("/health");
      return `${c.green("●")} ${api.base}  worklog: ${h.worklog}`;
    }
    default:
      throw new CliError(`알 수 없는 명령: ${cmd}`);
  }
}

const REPL_HELP = `${c.bold("zaevis")} — 그냥 입력하면 검색합니다.
  :log [YYYY-MM]      월별 로그          :projects        프로젝트 목록
  :project <slug>     프로젝트 상세      :summary [YYYY-MM] 월간 정리
  :index              색인 상태          :refresh         색인 갱신
  :add <내용>         한 줄 기록 (#태그 [[프로젝트]])
  :inbox              inbox 보기         :sources         데이터소스 상태
  :help               도움말             :quit            종료`;

async function repl(api: Api): Promise<void> {
  console.log(REPL_HELP + "\n");
  const rl = createInterface({ input: stdin, output: stdout, prompt: c.cyan("zaevis› ") });
  let closed = false;
  rl.on("close", () => (closed = true));
  const prompt = () => {
    if (!closed) rl.prompt();
  };
  prompt();
  // Async iteration (not rl.question) so piped input is processed line by line too.
  for await (const raw of rl) {
    const line = raw.trim();
    if (line === ":quit" || line === ":q" || line === "exit") break;
    if (line === ":help" || line === "?") {
      console.log(REPL_HELP);
    } else if (line) {
      try {
        if (line.startsWith(":") || line.startsWith("/")) {
          const [cmd, ...rest] = line.slice(1).split(/\s+/);
          const mapped = cmd === "refresh" ? "index" : cmd;
          const args = cmd === "refresh" ? ["--refresh"] : rest;
          console.log((await runLocal(mapped, args)) ?? (await run(api, mapped, args)));
        } else {
          console.log(await run(api, "search", [line]));
        }
      } catch (err) {
        console.log(c.red(err instanceof CliError ? err.message : `오류: ${(err as Error).message}`));
      }
      console.log();
    }
    prompt();
  }
  rl.close();
}

async function main(): Promise<void> {
  const [cmd = "repl", ...args] = process.argv.slice(2);
  const api = new Api(baseUrl());
  try {
    if (cmd === "repl") return await repl(api);
    const local = await runLocal(cmd, args);
    console.log(local ?? (await run(api, cmd, args)));
  } catch (err) {
    const msg = err instanceof CliError ? err.message : (err as Error)?.cause ? `서버에 연결할 수 없습니다: ${api.base}` : String((err as Error)?.message ?? err);
    console.error(c.red(msg));
    process.exitCode = 1;
  }
}

const invokedDirectly = process.argv[1] !== undefined && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
if (invokedDirectly) await main();
