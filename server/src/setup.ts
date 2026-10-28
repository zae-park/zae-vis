// `zaevis setup`: creates the personal worklog folder and wires AutoRAG + the daily schedule to it.
// Safe to re-run: existing files are never overwritten. Runs the same on macOS, Windows and Linux
// (this replaced kit/setup.sh). The app's first-run wizard calls it with explicit values.

import { execFileSync, spawn } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, relative, resolve, sep } from "node:path";
import { loadState, saveState, stateDir } from "./config.ts";
import { installSchedule, scheduleStatus } from "./schedule.ts";

const WIN = process.platform === "win32";

export type SetupOptions = {
  worklogDir?: string;
  reposRoot?: string;
  dailyAt?: string;
  disabled?: string[];
  autorag?: boolean; // default true
  skipRefresh?: boolean; // the app runs the first collect itself
  schedule?: boolean; // default true
  claudeMd?: boolean; // write CLAUDE.md into reposRoot
};

export type SetupContext = {
  root: string; // repo checkout or app payload: has kit/, server/, bin/
  home?: string;
  log?: (line: string) => void;
};

const expandHome = (p: string, home: string): string => (p === "~" ? home : p.startsWith("~/") ? join(home, p.slice(2)) : p);

function render(src: string, dest: string, vars: Record<string, string>, log: (l: string) => void): void {
  if (existsSync(dest)) {
    log(`  = ${dest} (있음, 건너뜀)`);
    return;
  }
  mkdirSync(dirname(dest), { recursive: true });
  let text = readFileSync(src, "utf8");
  for (const [k, v] of Object.entries(vars)) text = text.replaceAll(`{{${k}}}`, v);
  writeFileSync(dest, text);
  log(`  + ${dest}`);
}

/** The month file name and the .state.md default (7 days ago) the way the shell script made them. */
export function month(d = new Date()): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}
export function daysAgo(n: number, d = new Date()): string {
  const x = new Date(d);
  x.setDate(x.getDate() - n);
  return x.toISOString().slice(0, 10);
}

function gitTop(dir: string): string | null {
  try {
    return execFileSync("git", ["-C", dir, "rev-parse", "--show-toplevel"], { stdio: ["ignore", "pipe", "ignore"] }).toString().trim() || null;
  } catch {
    return null;
  }
}

/** Keeps the personal log out of a repository that happens to contain it (.git/info/exclude). */
export function excludeFromGit(paths: string[], roots: string[], log: (l: string) => void): void {
  for (const dir of roots) {
    const top = gitTop(dir);
    if (!top || !existsSync(join(top, ".git"))) continue;
    const ex = join(top, ".git", "info", "exclude");
    const realTop = realpathSync(top);
    for (const p of paths) {
      const real = existsSync(p) ? realpathSync(p) : join(realpathSync(dirname(p)), basename(p)); // CLAUDE.md may not exist yet
      const relRaw = relative(realTop, real);
      if (!relRaw || relRaw === ".." || relRaw.startsWith(`..${sep}`) || relRaw.startsWith("../")) continue;
      const rel = relRaw.split(sep).join("/");
      const line = `/${rel}`;
      const cur = existsSync(ex) ? readFileSync(ex, "utf8").split("\n") : [];
      if (cur.includes(line)) continue;
      mkdirSync(dirname(ex), { recursive: true });
      appendFileSync(ex, (cur.length && !readFileSync(ex, "utf8").endsWith("\n") ? "\n" : "") + line + "\n");
      log(`  + ${ex} 에 ${line} 추가 (커밋 방지)`);
    }
  }
}

export function which(name: string, env: NodeJS.ProcessEnv = process.env): string | null {
  const exts = WIN ? [".exe", ".cmd", ".bat", ""] : [""];
  for (const dir of (env.PATH ?? "").split(WIN ? ";" : ":")) {
    if (!dir) continue;
    for (const ext of exts) {
      const p = join(dir, name + ext);
      if (existsSync(p)) return p;
    }
  }
  return null;
}

/** node_modules/.bin/<name> (the .cmd shim on Windows) inside the server folder. */
export function serverBin(root: string, name: string): string {
  return join(root, "server", "node_modules", ".bin", WIN ? `${name}.cmd` : name);
}

export async function exec(cmd: string, args: string[], opts: { env?: NodeJS.ProcessEnv; cwd?: string } = {}): Promise<void> {
  await new Promise<void>((res, rej) => {
    const child = spawn(cmd, args, { stdio: "inherit", env: opts.env ?? process.env, cwd: opts.cwd, shell: WIN && cmd.endsWith(".cmd") });
    child.on("error", rej);
    child.on("close", (code) => (code === 0 ? res() : rej(new Error(`${basename(cmd)} 종료 코드 ${code}`))));
  });
}

export async function runSetup(opts: SetupOptions, ctx: SetupContext): Promise<void> {
  const log = ctx.log ?? ((l) => console.log(l));
  const home = ctx.home ?? homedir();
  const state = stateDir();
  const kit = join(ctx.root, "kit");
  const worklog = resolve(expandHome(opts.worklogDir ?? join(home, "worklog"), home));
  const repos = resolve(expandHome(opts.reposRoot ?? home, home));
  const dailyAt = opts.dailyAt ?? "18:30";
  const vars = { WORKLOG_DIR: worklog, REPOS_ROOT: repos };

  log(`1) worklog 폴더: ${worklog}`);
  for (const d of ["inbox/transcripts", "inbox/claude-sessions", "inbox/audio", "processed/transcripts", "processed/claude-sessions", "processed/audio", "log", "projects", "summaries", "sources"]) {
    mkdirSync(join(worklog, d), { recursive: true });
  }
  render(join(kit, "templates", "worklog", "README.md"), join(worklog, "README.md"), vars, log);
  render(join(kit, "templates", "worklog", "projects", "_template.md"), join(worklog, "projects", "_template.md"), vars, log);
  const m = month();
  if (!existsSync(join(worklog, "log", `${m}.md`))) {
    writeFileSync(join(worklog, "log", `${m}.md`), `# ${m} 로그\n\n`);
    log(`  + log/${m}.md`);
  }
  if (!existsSync(join(worklog, ".state.md"))) writeFileSync(join(worklog, ".state.md"), `last_weekly: ${daysAgo(7)}\n`);

  if (opts.claudeMd) {
    log(`2) Claude 세션 노트 지침: ${join(repos, "CLAUDE.md")}`);
    const dest = join(repos, "CLAUDE.md");
    if (existsSync(dest) && !readFileSync(dest, "utf8").includes("zaevis")) {
      log("  ! 기존 CLAUDE.md가 있어 덮어쓰지 않습니다. 아래 파일 내용을 직접 붙여 넣으세요:");
      render(join(kit, "claude", "CLAUDE.md"), join(state, "CLAUDE.snippet.md"), vars, log);
    } else {
      render(join(kit, "claude", "CLAUDE.md"), dest, vars, log);
    }
  } else {
    log("2) Claude Code·Codex·Gemini CLI 작업은 에이전트 세션 데이터소스가 로컬 기록에서 직접 모읍니다 (CLAUDE.md 불필요)");
  }
  excludeFromGit([worklog, join(repos, "CLAUDE.md")], [worklog, repos], log);

  log(`3) 예약 작업 프롬프트: ${join(state, "weekly-task-prompt.md")}`);
  render(join(kit, "claude", "weekly-task-prompt.md"), join(state, "weekly-task-prompt.md"), vars, log);

  const autoragConfig = join(state, "autorag", "config.json");
  mkdirSync(state, { recursive: true });
  const configFile = join(state, "config.json");
  if (existsSync(configFile)) {
    log(`  = ${configFile} (있음, 건너뜀 — 바꾸려면 앱 설정 화면이나 파일을 직접 수정)`);
  } else {
    writeFileSync(configFile, JSON.stringify({ worklogDir: worklog, reposRoot: repos, autoragConfig, port: 4710, dailyAt, indexOnInject: false }, null, 2) + "\n");
    log(`  + ${configFile}`);
  }
  const sourcesFile = join(state, "sources.json");
  if (!existsSync(sourcesFile)) {
    const s: Record<string, unknown> = {};
    for (const name of opts.disabled ?? []) s[name] = { enabled: false };
    s.custom = [];
    writeFileSync(sourcesFile, JSON.stringify(s, null, 2) + "\n");
    log(`  + ${sourcesFile}`);
  }

  if (opts.autorag !== false) {
    log("4) AutoRAG Lite (검색 색인, 모델·API 키 불필요)");
    const major = Number(process.versions.node.split(".")[0]);
    if (major < 24) throw new Error(`Node.js 24 이상이 필요합니다 (현재 ${process.versions.node}).`);
    if (!which("minsync")) {
      const missing = ["cargo", "protoc", "cmake"].filter((t) => !which(t));
      if (missing.length) {
        throw new Error(`임베딩 엔진 MinSync를 빌드하려면 ${missing.join(", ")}가 필요합니다. (검색 없이 쓰려면 --no-autorag)\n    Rust: https://rustup.rs · protobuf/cmake: brew install protobuf cmake (Windows: winget 또는 choco)`);
      }
    }
    if (!existsSync(join(ctx.root, "server", "node_modules"))) await exec(WIN ? "npm.cmd" : "npm", ["install", "--no-fund", "--no-audit"], { cwd: join(ctx.root, "server") });
    if (!existsSync(autoragConfig)) {
      mkdirSync(dirname(autoragConfig), { recursive: true });
      await exec(serverBin(ctx.root, "autorag"), ["lite", "init", "--search-paths", worklog, "--languages", "ko,en"], { env: { ...process.env, AUTORAG_CONFIG: autoragConfig } });
      // lite init writes OpenRouter defaults; nothing external until the user turns re-ranking on in the app
      const c = JSON.parse(readFileSync(autoragConfig, "utf8")) as Record<string, unknown>;
      delete c.jev;
      delete c.queryDecomposition;
      c.rerank = false;
      writeFileSync(autoragConfig, JSON.stringify(c, null, 2) + "\n");
    }
    if (!which("minsync")) {
      log("  MinSync 빌드 중 (처음 한 번, 수 분 걸림)…");
      await exec(which("cargo")!, ["install", "minsync", "--locked"]);
    }
    if (!opts.skipRefresh) {
      log("  색인 생성 중…");
      await exec(serverBin(ctx.root, "autorag"), ["lite", "refresh"], { env: { ...process.env, AUTORAG_CONFIG: autoragConfig } });
    }
  }

  // The app runs the first collect right after setup; the schedule below would otherwise start a
  // second collect + index at the same time (MinSync holds a lock). Mark today as done.
  if (opts.skipRefresh && !existsSync(join(state, "state.json"))) {
    const s = loadState();
    s.daily = { lastRun: new Date().toISOString(), ok: true, index: "첫 수집은 앱이 진행" };
    saveState(s);
  }

  if (opts.schedule !== false) {
    const st = await scheduleStatus(dailyAt);
    if (st.supported) {
      log(`5) 매일 수집·색인 예약 (${process.platform === "darwin" ? "launchd" : process.platform === "win32" ? "작업 스케줄러" : "cron"})`);
      try {
        const r = await installSchedule(dailyAt);
        log(`  ● 매일 ${r.dailyAt ?? dailyAt} 수집·색인`);
      } catch (err) {
        log(`  ! 예약 등록 실패 — 나중에 'zaevis schedule install' (${(err as Error).message})`);
      }
    } else {
      log(`5) 자동 예약은 이 OS에서 지원하지 않습니다. ${st.hint ?? ""}`);
    }
  }

  log(`
완료.
- 터미널:      zaevis run cli
- 브라우저:    zaevis run web
- 데스크톱 앱: zaevis run app
- 지금 수집:   zaevis collect          (매일 자동: zaevis schedule)
- 녹음 전사:   zaevis ext install whisperx`);
}

/** Parses `zaevis setup` flags (the shell script's names kept for the app wizard). */
export function parseSetupArgs(argv: string[]): SetupOptions {
  const o: SetupOptions = { disabled: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i] ?? "";
    switch (a) {
      case "--worklog": o.worklogDir = next(); break;
      case "--repos": o.reposRoot = next(); break;
      case "--daily-at": o.dailyAt = next(); break;
      case "--disable": o.disabled!.push(next()); break;
      case "--no-autorag": o.autorag = false; break;
      case "--skip-refresh": o.skipRefresh = true; break;
      case "--no-schedule": o.schedule = false; break;
      case "--claude-md": o.claudeMd = true; break;
      case "--email": next(); break; // no longer used: git collects every author
      case "--any-author": case "--yes": case "-y": break;
      default: throw new Error(`알 수 없는 옵션: ${a}`);
    }
  }
  return o;
}

/** Validates "HH:MM" the way the scheduler does; here so setup fails before writing anything. */
export function assertTime(hhmm: string): void {
  if (!/^\d{1,2}:\d{2}$/.test(hhmm)) throw new Error(`시각 형식이 올바르지 않습니다: ${hhmm} (예: 18:30)`);
}
