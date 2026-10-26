#!/usr/bin/env node
// The `zaevis` command, one implementation for macOS, Windows and Linux. `bin/zaevis` (sh) and
// `bin/zaevis.cmd` only find a Node and run this file. The app bundle runs it the same way.
//
//   node src/zaevis.ts <command> [args…]      see usage() below

import { spawn, spawnSync } from "node:child_process";
import { appendFileSync, closeSync, existsSync, mkdirSync, openSync, readFileSync, readSync, readdirSync, statSync, symlinkSync, unlinkSync, watchFile, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, delimiter, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadConfig, stateDir } from "./config.ts";
import { scheduleStatus } from "./schedule.ts";
import { exec, parseSetupArgs, runSetup, which } from "./setup.ts";

const WIN = process.platform === "win32";
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SERVER = join(ROOT, "server");
const APP = join(ROOT, "app");
const STATE = stateDir();
const PID_FILE = join(STATE, "server.pid");
const LOG_FILE = join(STATE, "server.log");
/** Inside the app bundle: the Node runtime, MinSync and the web build travel with us. */
const BUNDLED = existsSync(join(ROOT, "node", WIN ? "node.exe" : join("bin", "node")));
const BUILD = BUNDLED && existsSync(join(ROOT, "VERSION")) ? readFileSync(join(ROOT, "VERSION"), "utf8").trim() : "";

if (BUNDLED) {
  process.env.PATH = [join(ROOT, "node", WIN ? "" : "bin"), join(ROOT, "bin"), process.env.PATH ?? ""].join(delimiter);
  process.env.ZAEVIS_WEB_DIR ??= join(ROOT, "web");
  if (BUILD) process.env.ZAEVIS_BUILD = BUILD;
}

const tty = process.stdout.isTTY && !process.env.NO_COLOR;
const paint = (code: string) => (s: string) => (tty ? `\x1b[${code}m${s}\x1b[0m` : s);
const B = paint("1"), D = paint("2"), R = paint("31"), G = paint("32"), Y = paint("33");
const say = (s: string) => console.log(s);
const info = (s: string) => console.log(`${D("›")} ${s}`);
const warn = (s: string) => console.error(`${Y("!")} ${s}`);
const die = (s: string): never => {
  console.error(`${R("✗")} ${s}`);
  process.exit(1);
};

function usage(): void {
  say(`${B("zaevis")} — 작업 기록 · 지식 관리

${B("실행")}
  zaevis run cli              터미널에서 검색·로그 보기 (대화형)
  zaevis run web [--rebuild]  브라우저로 열기 (필요하면 웹 앱을 빌드)
  zaevis run app [--release]  데스크톱 앱 실행 (기본: flutter 개발 모드, --release: 빌드 후 실행)
  zaevis run server           API 서버를 이 터미널에서 실행 (foreground)

${B("바로 쓰기")}
  zaevis search <검색어>      검색           zaevis log [YYYY-MM]     월별 로그
  zaevis projects             프로젝트 목록  zaevis summary [YYYY-MM] 월간 정리
  zaevis index [--refresh]    색인 상태 / 갱신 (--force: 처음부터)
  zaevis digest [--run]       주간 정리(지식화) 상태 / 지금 실행 — 설치된 에이전트(Claude Code·Codex·Gemini) 또는 OpenRouter 키로

${B("기록 넣기 (실시간)")}
  zaevis add "#decision [[프로젝트]] 무엇을, 왜"   한 줄 기록
  zaevis ingest <파일…>       전사본(.txt .md .vtt .srt)은 inbox로, 녹음은 whisperX로 바로 전사
  zaevis inbox                inbox와 전사 작업 보기

${B("수집 (배치)")}
  zaevis collect [이름…]      지금 수집하고 색인 (--no-index: 색인 생략)
  zaevis sources [on|off 이름]  데이터소스 상태 / 켜기·끄기
  zaevis schedule [install [HH:MM]|remove]   매일 수집·색인 예약 (macOS launchd · Windows 작업 스케줄러)
  zaevis daily [--if-stale]   예약이 실행하는 명령 (수집 + 색인)

${B("관리")}
  zaevis install              'zaevis' 명령을 PATH에 등록
  zaevis setup [옵션]         worklog 폴더·AutoRAG·예약 초기 설정
  zaevis build web|app        앱 빌드만
  zaevis start | stop | status | logs   백그라운드 서버 관리
  zaevis ext install whisperx  녹음 전사 확장 설치 (<상태 폴더>/ext/whisperx)
  zaevis doctor               필요한 도구 점검`);
}

// ── helpers ────────────────────────────────────────────────────────────────

const port = (): number => loadConfig().port;
const url = (): string => `http://127.0.0.1:${port()}`;

async function health(): Promise<{ ok: boolean; build?: string } | null> {
  try {
    const res = await fetch(`${url()}/api/health`, { signal: AbortSignal.timeout(2000) });
    if (!res.ok) return null;
    return (await res.json()) as { ok: boolean; build?: string };
  } catch {
    return null;
  }
}

function pidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function readPid(): number | null {
  try {
    const n = Number(readFileSync(PID_FILE, "utf8").trim());
    return Number.isInteger(n) && n > 0 ? n : null;
  } catch {
    return null;
  }
}

function killPid(pid: number): void {
  if (WIN) spawnSync("taskkill", ["/PID", String(pid), "/T", "/F"], { stdio: "ignore" });
  else process.kill(pid, "SIGTERM");
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function needNode(): void {
  const major = Number(process.versions.node.split(".")[0]);
  if (major < 24) die(`Node.js 24 이상이 필요합니다 (현재 ${process.version}): https://nodejs.org`);
  if (!existsSync(join(SERVER, "node_modules"))) {
    if (BUNDLED) die(`앱 파일이 손상되었습니다 (${join(SERVER, "node_modules")} 없음). zaevis를 다시 설치하세요.`);
    info("서버 의존성 설치 중…");
    spawnSync(WIN ? "npm.cmd" : "npm", ["install", "--no-fund", "--no-audit", "--silent"], { cwd: SERVER, stdio: "inherit", shell: WIN });
  }
}

function needFlutter(): string {
  if (BUNDLED) die("앱 설치본에서는 빌드하지 않습니다. 앱을 쓰려면 'zaevis run app'.");
  return which("flutter") ?? die("Flutter가 필요합니다: https://docs.flutter.dev/get-started/install");
}

function hostDevice(): string {
  return WIN ? "windows" : process.platform === "darwin" ? "macos" : "linux";
}

function openUrl(target: string): void {
  if (process.platform === "darwin") spawn("open", [target], { stdio: "ignore", detached: true }).unref();
  else if (WIN) spawn("cmd", ["/c", "start", "", target], { stdio: "ignore", detached: true, windowsHide: true }).unref();
  else if (which("xdg-open")) spawn("xdg-open", [target], { stdio: "ignore", detached: true }).unref();
  else say(`브라우저에서 여세요: ${target}`);
}

/** Runs another src/*.ts entry with this Node, inheriting the terminal. Resolves with its exit code. */
function child(script: string, args: string[], extraEnv: NodeJS.ProcessEnv = {}): Promise<number> {
  return new Promise((res) => {
    const c = spawn(process.execPath, [join(SERVER, "src", script), ...args], { stdio: "inherit", cwd: SERVER, env: { ...process.env, ...extraEnv } });
    c.on("exit", (code) => res(code ?? 1));
    c.on("error", () => res(1));
  });
}

// ── server lifecycle ───────────────────────────────────────────────────────

async function serverStart(): Promise<void> {
  const h = await health();
  if (h) {
    // the app was replaced while an older build's server kept running
    const stale = BUILD !== "" && (h.build ?? "") !== BUILD;
    const pid = readPid();
    if (!(stale && pid && pidAlive(pid))) return;
    info("이전 빌드의 서버가 떠 있어 다시 시작합니다");
    killPid(pid);
    unlinkSync(PID_FILE);
    for (let i = 0; i < 20 && (await health()); i++) await sleep(250);
  }
  needNode();
  mkdirSync(STATE, { recursive: true });
  info(`서버 시작 (${url()})`);
  const log = openSync(LOG_FILE, "a");
  const proc = spawn(process.execPath, [join(SERVER, "src", "main.ts")], { cwd: SERVER, detached: !WIN, stdio: ["ignore", log, log], env: process.env, windowsHide: true });
  closeSync(log);
  proc.unref();
  writeFileSync(PID_FILE, String(proc.pid));
  for (let i = 0; i < 40; i++) {
    if (await health()) return;
    if (proc.exitCode !== null || !pidAlive(proc.pid!)) {
      console.error(tail(LOG_FILE, 20));
      die(`서버가 시작되지 않았습니다. 처음이라면 'zaevis setup'을 먼저 실행하세요. (로그: ${LOG_FILE})`);
    }
    await sleep(250);
  }
  die(`서버 응답이 없습니다 (로그: ${LOG_FILE})`);
}

async function serverStop(): Promise<void> {
  const pid = readPid();
  if (pid && pidAlive(pid)) {
    killPid(pid);
    try {
      unlinkSync(PID_FILE);
    } catch {}
    say(`${G("●")} 서버를 멈췄습니다.`);
  } else if (await health()) {
    warn(`zaevis가 띄우지 않은 서버가 ${url()}에서 돌고 있습니다. 직접 종료하세요.`);
  } else {
    say("실행 중인 서버가 없습니다.");
  }
}

async function serverStatus(): Promise<void> {
  say((await health()) ? `${G("●")} 서버 실행 중: ${url()}` : `${D("○")} 서버 꺼짐 (${url()})`);
}

function tail(file: string, n: number): string {
  try {
    return readFileSync(file, "utf8").trimEnd().split("\n").slice(-n).join("\n");
  } catch {
    return "";
  }
}

function logsFollow(): void {
  mkdirSync(STATE, { recursive: true });
  if (!existsSync(LOG_FILE)) writeFileSync(LOG_FILE, "");
  say(tail(LOG_FILE, 50));
  let size = statSync(LOG_FILE).size;
  watchFile(LOG_FILE, { interval: 500 }, (cur) => {
    if (cur.size <= size) {
      size = cur.size;
      return;
    }
    const fd = openSync(LOG_FILE, "r");
    const buf = Buffer.alloc(cur.size - size);
    readSyncAll(fd, buf, size);
    closeSync(fd);
    size = cur.size;
    process.stdout.write(buf.toString());
  });
}
function readSyncAll(fd: number, buf: Buffer, pos: number): void {
  let off = 0;
  while (off < buf.length) {
    const n = readSync(fd, buf, off, buf.length - off, pos + off);
    if (n <= 0) break;
    off += n;
  }
}

// ── flutter (development checkout only) ───────────────────────────────────

function ensurePlatform(p: string): void {
  if (existsSync(join(APP, p))) return;
  info(`${p} 플랫폼 폴더 생성`);
  spawnSync(WIN ? "bash" : "bash", [join(APP, "tool", "setup_platforms.sh"), p], { stdio: "inherit", cwd: APP });
}

function webStale(): boolean {
  const index = join(APP, "build", "web", "index.html");
  if (!existsSync(index)) return true;
  const t = statSync(index).mtimeMs;
  const newer = (dir: string): boolean => {
    for (const e of readdirSafe(dir)) {
      const p = join(dir, e);
      const s = statSync(p);
      if (s.isDirectory() ? newer(p) : s.mtimeMs > t) return true;
    }
    return false;
  };
  return newer(join(APP, "lib")) || statSync(join(APP, "pubspec.yaml")).mtimeMs > t;
}
function readdirSafe(dir: string): string[] {
  try {
    return readdirSync(dir);
  } catch {
    return [];
  }
}

async function buildWeb(): Promise<void> {
  const flutter = needFlutter();
  ensurePlatform("web");
  info("웹 앱 빌드 중…");
  await exec(flutter, ["build", "web", "--release"], { cwd: APP });
}

async function buildApp(): Promise<void> {
  const flutter = needFlutter();
  const dev = hostDevice();
  ensurePlatform(dev);
  info(`${dev} 앱 빌드 중…`);
  await exec(flutter, ["build", dev, "--release"], { cwd: APP });
}

function openBuiltApp(): void {
  const dev = hostDevice();
  if (dev === "macos") spawn("open", [join(APP, "build", "macos", "Build", "Products", "Release", "zaevis.app")], { stdio: "ignore" }).unref();
  else if (dev === "windows") spawn(join(APP, "build", "windows", "x64", "runner", "Release", "zaevis.exe"), [], { stdio: "ignore", detached: true }).unref();
  else {
    const bundle = join(APP, "build", "linux");
    for (const arch of readdirSafe(bundle)) spawn(join(bundle, arch, "release", "bundle", "zaevis"), [], { stdio: "ignore", detached: true }).unref();
  }
}

function appBundle(): string | null {
  let p = ROOT;
  while (p !== dirname(p)) {
    if (p.endsWith(".app")) return p;
    p = dirname(p);
  }
  return null;
}

// ── install / ext / doctor ─────────────────────────────────────────────────

function cmdInstall(): void {
  if (WIN) {
    const binDir = process.env.ZAEVIS_BIN_DIR ?? join(process.env.LOCALAPPDATA ?? join(homedir(), "AppData", "Local"), "zaevis", "bin");
    mkdirSync(binDir, { recursive: true });
    writeFileSync(join(binDir, "zaevis.cmd"), `@echo off\r\n"${join(ROOT, "bin", "zaevis.cmd")}" %*\r\n`);
    say(`${G("✓")} ${join(binDir, "zaevis.cmd")}`);
    const cur = spawnSync("powershell", ["-NoProfile", "-Command", "[Environment]::GetEnvironmentVariable('Path','User')"], { encoding: "utf8" }).stdout?.trim() ?? "";
    if (!cur.split(";").includes(binDir)) {
      spawnSync("powershell", ["-NoProfile", "-Command", `[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';${binDir}', 'User')`], { stdio: "inherit" });
      say(`${G("✓")} 사용자 PATH에 추가했습니다. 새 터미널을 열어 'zaevis'를 쓰세요.`);
    } else say("이제 어디서든 'zaevis'를 쓸 수 있습니다.");
    return;
  }
  const binDir = process.env.ZAEVIS_BIN_DIR ?? join(homedir(), ".local", "bin");
  mkdirSync(binDir, { recursive: true });
  const link = join(binDir, "zaevis");
  try {
    unlinkSync(link);
  } catch {}
  symlinkSync(join(ROOT, "bin", "zaevis"), link);
  say(`${G("✓")} ${link} → ${join(ROOT, "bin", "zaevis")}`);
  if ((process.env.PATH ?? "").split(delimiter).includes(binDir)) {
    say("이제 어디서든 'zaevis'를 쓸 수 있습니다.");
    return;
  }
  const rc = (process.env.SHELL ?? "").endsWith("bash") ? join(homedir(), ".bashrc") : join(homedir(), ".zshrc");
  const cur = existsSync(rc) ? readFileSync(rc, "utf8") : "";
  if (!cur.includes("# zaevis")) {
    appendFileSync(rc, `\nexport PATH="${binDir}:$PATH"  # zaevis\n`);
    say(`${G("✓")} ${rc} 에 PATH를 추가했습니다.`);
  }
  say(`새 터미널을 열거나 'source ${rc}' 후 'zaevis'를 쓰세요.`);
}

async function extInstallWhisperx(): Promise<void> {
  // Needs nothing preinstalled: uv fetches Python 3.12, imageio-ffmpeg ships an ffmpeg binary.
  const venv = join(STATE, "ext", "whisperx");
  let uv = which("uv");
  if (!uv) {
    uv = join(STATE, "ext", "uv", WIN ? "uv.exe" : "uv");
    if (!existsSync(uv)) {
      info("uv 내려받는 중 (Python 설치 도구)");
      mkdirSync(dirname(uv), { recursive: true });
      if (WIN) await exec("powershell", ["-NoProfile", "-ExecutionPolicy", "ByPass", "-Command", `$env:UV_UNMANAGED_INSTALL='${dirname(uv)}'; irm https://astral.sh/uv/install.ps1 | iex`]);
      else await exec("sh", ["-c", `curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="${dirname(uv)}" sh`]);
    }
  }
  info(`whisperX 설치 중 → ${venv} (수 분, 1~2GB)`);
  await exec(uv, ["venv", "--allow-existing", "--python", "3.12", venv]);
  const py = WIN ? join(venv, "Scripts", "python.exe") : join(venv, "bin", "python");
  await exec(uv, ["pip", "install", "--python", py, "whisperx", "imageio-ffmpeg"]);
  const ff = spawnSync(py, ["-c", "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())"], { encoding: "utf8" }).stdout.trim();
  const link = WIN ? join(venv, "Scripts", "ffmpeg.exe") : join(venv, "bin", "ffmpeg");
  try {
    unlinkSync(link);
  } catch {}
  if (WIN) writeFileSync(link, readFileSync(ff));
  else symlinkSync(ff, link);
  say(`${G("✓")} whisperX 설치 완료. 앱에서 녹음을 올리거나 'zaevis ingest 녹음.m4a'.`);
  say("  화자 구분이 필요하면 HF_TOKEN 환경변수를 설정하세요 (pyannote 모델 동의 필요).");
}

async function doctor(): Promise<void> {
  let ok = true;
  const check = (name: string, hint: string, versionArgs = ["--version"]) => {
    const bin = which(name);
    if (!bin) {
      say(`${R("✗")} ${name}  ${D(hint)}`);
      ok = false;
      return;
    }
    const v = spawnSync(bin, versionArgs, { encoding: "utf8", shell: WIN && bin.endsWith(".cmd") }).stdout?.split("\n")[0] ?? "";
    say(`${G("✓")} ${name}  ${D(v.trim())}`);
  };
  check("node", "https://nodejs.org (24 이상)", ["-v"]);
  check("flutter", "https://docs.flutter.dev/get-started/install");
  check("cargo", "https://rustup.rs (MinSync 빌드용)");
  check("protoc", "protobuf (MinSync 빌드용)");
  check("cmake", "cmake (MinSync 빌드용)");
  check("minsync", "zaevis setup이 빌드합니다");
  const wx = join(STATE, "ext", "whisperx", WIN ? "Scripts" : "bin", WIN ? "whisperx.exe" : "whisperx");
  say(existsSync(wx) || which("whisperx") ? `${G("✓")} whisperx` : `${D("○")} whisperx  ${D("선택: zaevis ext install whisperx")}`);
  if (existsSync(join(STATE, "config.json"))) say(`${G("✓")} 설정  ${D(join(STATE, "config.json"))}`);
  else {
    say(`${R("✗")} 설정  ${D("zaevis setup 필요")}`);
    ok = false;
  }
  await serverStatus();
  const st = await scheduleStatus();
  say(st.installed ? `${G("●")} 매일 ${st.dailyAt} 수집·색인 ${st.loaded ? "" : D("(등록됐지만 로드되지 않음)")}` : `${D("○")} 예약 없음 ${st.hint ? D(st.hint) : ""}`);
  if (!ok) process.exitCode = 1;
}

// ── dispatch ───────────────────────────────────────────────────────────────

async function main(argv: string[]): Promise<void> {
  const [cmd = "help", ...rest] = argv;
  switch (cmd) {
    case "run": {
      const [target, ...opts] = rest;
      switch (target) {
        case "cli":
          await serverStart();
          process.exitCode = await child("cli.ts", ["repl"]);
          return;
        case "web":
          if (!BUNDLED && (opts[0] === "--rebuild" || webStale())) await buildWeb();
          await serverStart();
          say(`${G("●")} ${url()}`);
          openUrl(url());
          return;
        case "app": {
          if (BUNDLED) {
            const bundle = appBundle();
            if (bundle) spawn("open", [bundle], { stdio: "ignore" }).unref();
            else openUrl(url());
            return;
          }
          await serverStart();
          if (opts[0] === "--release") {
            await buildApp();
            openBuiltApp();
            return;
          }
          const flutter = needFlutter();
          const dev = hostDevice();
          ensurePlatform(dev);
          await exec(flutter, ["run", "-d", dev, ...opts], { cwd: APP });
          return;
        }
        case "server":
          needNode();
          process.exitCode = await child("main.ts", []);
          return;
        default:
          die("사용법: zaevis run cli|web|app|server");
      }
      return;
    }
    case "build":
      if (rest[0] === "web") return buildWeb();
      if (rest[0] === "app") return buildApp();
      die("사용법: zaevis build web|app");
      return;
    case "search": case "s": case "log": case "l": case "projects": case "p": case "project": case "summary": case "index": case "add": case "inbox": case "digest":
      await serverStart();
      needNode();
      process.exitCode = await child("cli.ts", [cmd, ...rest]);
      return;
    case "sources": case "schedule": case "ingest":
      needNode();
      process.exitCode = await child("cli.ts", [cmd, ...rest]);
      return;
    case "daily":
      needNode();
      process.exitCode = await child("daily.ts", rest);
      return;
    case "collect": {
      needNode();
      const args: string[] = [];
      for (const a of rest) a.startsWith("--") ? args.push(a) : args.push("--source", a);
      process.exitCode = await child("daily.ts", args);
      return;
    }
    case "ext":
      if (rest[0] === "install" && rest[1] === "whisperx") return extInstallWhisperx();
      die("사용법: zaevis ext install whisperx");
      return;
    case "start":
      await serverStart();
      await serverStatus();
      return;
    case "stop":
      return serverStop();
    case "status":
      return serverStatus();
    case "logs":
      return logsFollow();
    case "setup": {
      let opts;
      try {
        opts = parseSetupArgs(rest);
      } catch (err) {
        die((err as Error).message);
      }
      needNode();
      await runSetup(opts!, { root: ROOT });
      return;
    }
    case "install":
      return cmdInstall();
    case "doctor":
      return doctor();
    case "help": case "-h": case "--help":
      return usage();
    default:
      usage();
      die(`알 수 없는 명령: ${cmd}`);
  }
}

try {
  await main(process.argv.slice(2));
} catch (err) {
  die((err as Error).message);
}
