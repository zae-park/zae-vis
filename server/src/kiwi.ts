// Korean morphological analysis for keyword (BM25) search.
//
// AutoRAG always asks MinSync for its `multilingual` tokenizer, which keeps every whitespace word and
// adds the morphemes Kiwi finds, so "인증서를" matches "인증서" and "연구목표" still matches exactly.
// MinSync loads Kiwi at run time (through kiwi-rs): the native library (libkiwi.dylib / libkiwi.so /
// kiwi.dll) and the base model folder (models/cong/base). Neither ships with MinSync or the app.
// When they are missing AutoRAG falls back to whitespace tokens and reports `lexical-tokenizer-unavailable`.
//
// `zaevis ext install kiwi` downloads both from Kiwi's GitHub release (pinned version, sha256 checked)
// into $ZAEVIS_HOME/ext/kiwi, and the server/daily job point the autorag-mcp child at them with
// KIWI_LIBRARY_PATH / KIWI_MODEL_PATH. Discovery mirrors kiwi-rs and AutoRAG's own probe: explicit env
// vars win (and are authoritative even when the path is missing), then this install, then ~/.local/kiwi,
// then the system folders.

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { createWriteStream, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { Readable, Transform } from "node:stream";
import { pipeline } from "node:stream/promises";
import { loadState, saveState, stateDir } from "./config.ts";

export const KIWI_VERSION = "0.24.1";
export const KIWI_REPO = "bab2min/Kiwi";

export type KiwiAsset = { name: string; sha256: string; bytes: number };

/** Release assets of KIWI_VERSION (sha256 from the GitHub release's asset digests). */
export const KIWI_ASSETS: { library: Record<string, KiwiAsset>; model: KiwiAsset } = {
  library: {
    "darwin-arm64": { name: `kiwi_mac_arm64_v${KIWI_VERSION}.tgz`, sha256: "510680643980c4af94bee57151020b6373a098bac809084e7cb26080fc5bd9b9", bytes: 41371847 },
    "darwin-x64": { name: `kiwi_mac_x86_64_v${KIWI_VERSION}.tgz`, sha256: "9042ea4ca99bbb57c8bd3574b2cb1542958734e1f1de8ff8fe6a6ad05e5f077a", bytes: 102887487 },
    "linux-x64": { name: `kiwi_lnx_x86_64_v${KIWI_VERSION}.tgz`, sha256: "534f3b507784ea0f2c26884a13c22f2bfa573f86b6c20b9856feb9050a88f47a", bytes: 75394334 },
    "linux-arm64": { name: `kiwi_lnx_aarch64_v${KIWI_VERSION}.tgz`, sha256: "ff15838604039130d24e2803ed87c2edc36665f9ff24be8a23b257c2860bc25b", bytes: 34868989 },
    "win32-x64": { name: `kiwi_win_x64_v${KIWI_VERSION}.zip`, sha256: "857576c5e8492ec66f8327e35572b20f286b092a8e760fe780ace1a99afc3b30", bytes: 38261195 },
  },
  model: { name: `kiwi_model_v${KIWI_VERSION}_base.tgz`, sha256: "50d163e1af817444ef21f7ec5ea07ef69fb347282d57a6b49260f2039d4dc346", bytes: 87967233 },
};

export const releaseUrl = (asset: KiwiAsset, version = KIWI_VERSION): string => `https://github.com/${KIWI_REPO}/releases/download/v${version}/${asset.name}`;

/** The dynamic library file name kiwi-rs loads on each platform. */
export function libraryFileName(platform: NodeJS.Platform = process.platform): string {
  return platform === "win32" ? "kiwi.dll" : platform === "darwin" ? "libkiwi.dylib" : "libkiwi.so";
}

/** Where `zaevis ext install kiwi` puts the library and model. */
export const kiwiDir = (): string => join(stateDir(), "ext", "kiwi");

export type KiwiEnvironment = {
  env: NodeJS.ProcessEnv;
  platform: NodeJS.Platform;
  arch: string;
  home: string | undefined;
  exists: (path: string) => boolean;
  /** zaevis's own install folder. */
  dir: string;
};

function defaultEnvironment(over: Partial<KiwiEnvironment> = {}): KiwiEnvironment {
  let home: string | undefined;
  try {
    home = homedir();
  } catch {
    home = undefined;
  }
  return { env: process.env, platform: process.platform, arch: process.arch, home, exists: existsSync, dir: kiwiDir(), ...over };
}

export type KiwiSource = "env" | "zaevis" | "user" | "system";

export type KiwiStatus = {
  /** Both the library and the model were found, so MinSync can tokenize Korean morphemes. */
  installed: boolean;
  library: string | null;
  model: string | null;
  /** Where the library came from (the model may come from elsewhere; env vars are reported as "env"). */
  source: KiwiSource | null;
  /** Version written by `zaevis ext install kiwi`, null when that install is absent. */
  version: string | null;
  /** zaevis's install folder. */
  dir: string;
  /** Library asset for this platform; null when the release has none (then only a manual install works). */
  asset: string | null;
  /** Download size of library + model, for the UI. */
  downloadMb: number;
};

function userRoots({ env, platform, home }: KiwiEnvironment): string[] {
  if (platform === "win32") {
    const roots: string[] = [];
    if (env.LOCALAPPDATA) roots.push(join(env.LOCALAPPDATA, "kiwi"));
    const profile = env.USERPROFILE ?? home;
    if (profile) roots.push(join(profile, "AppData", "Local", "kiwi"));
    return roots;
  }
  return home ? [join(home, ".local", "kiwi")] : [];
}

function systemLibraryDirs(platform: NodeJS.Platform): string[] {
  if (platform === "win32") return ["C:\\kiwi\\lib", "C:\\Program Files\\Kiwi\\lib"];
  return platform === "darwin" ? ["/usr/local/lib", "/opt/homebrew/lib"] : ["/usr/local/lib", "/usr/lib"];
}

function systemModelDirs(platform: NodeJS.Platform): string[] {
  if (platform === "win32") return ["C:\\kiwi\\models", "C:\\Program Files\\Kiwi\\models"];
  return platform === "darwin"
    ? ["/usr/local/models", "/opt/homebrew/models", "/usr/local/share/kiwi/models"]
    : ["/usr/local/models", "/usr/local/share/kiwi/models", "/usr/share/kiwi/models"];
}

/** Library candidates in search order, each with where it would come from. */
function libraryCandidates(e: KiwiEnvironment): Array<{ path: string; source: KiwiSource }> {
  const file = libraryFileName(e.platform);
  return [
    { path: join(e.dir, "lib", file), source: "zaevis" as const },
    ...userRoots(e).map((root) => ({ path: join(root, "lib", file), source: "user" as const })),
    ...systemLibraryDirs(e.platform).map((dir) => ({ path: join(dir, file), source: "system" as const })),
  ];
}

function modelCandidates(e: KiwiEnvironment): Array<{ path: string; source: KiwiSource }> {
  return [
    { path: join(e.dir, "models", "cong", "base"), source: "zaevis" as const },
    ...userRoots(e).map((root) => ({ path: join(root, "models", "cong", "base"), source: "user" as const })),
    ...systemModelDirs(e.platform).map((dir) => ({ path: join(dir, "cong", "base"), source: "system" as const })),
  ];
}

export function libraryAsset(platform: NodeJS.Platform = process.platform, arch: string = process.arch): KiwiAsset | null {
  return KIWI_ASSETS.library[`${platform}-${arch}`] ?? null;
}

/** Finds the Kiwi library and model the way kiwi-rs/AutoRAG will, so the status we show matches what MinSync does. */
export function probeKiwi(over: Partial<KiwiEnvironment> = {}): KiwiStatus {
  const e = defaultEnvironment(over);
  const pick = (explicit: string | undefined, candidates: Array<{ path: string; source: KiwiSource }>) => {
    if (explicit !== undefined && explicit !== "") return e.exists(explicit) ? { path: explicit, source: "env" as const } : null;
    return candidates.find((c) => e.exists(c.path)) ?? null;
  };
  const library = pick(e.env.KIWI_LIBRARY_PATH, libraryCandidates(e));
  const model = pick(e.env.KIWI_MODEL_PATH, modelCandidates(e));
  const versionFile = join(e.dir, "VERSION");
  let version: string | null = null;
  if (e.exists(versionFile)) {
    try {
      version = readFileSync(versionFile, "utf8").trim() || null;
    } catch {
      version = null;
    }
  }
  const asset = libraryAsset(e.platform, e.arch);
  return {
    installed: library !== null && model !== null,
    library: library?.path ?? null,
    model: model?.path ?? null,
    source: library?.source ?? model?.source ?? null,
    version,
    dir: e.dir,
    asset: asset?.name ?? null,
    downloadMb: Math.round(((asset?.bytes ?? 0) + KIWI_ASSETS.model.bytes) / 1_000_000),
  };
}

/**
 * Environment for the autorag-mcp child (and MinSync under it). Explicit paths are set only when we
 * found a pair; the user's own KIWI_* variables are left alone because the probe already honoured them.
 */
export function kiwiEnv(status: KiwiStatus = probeKiwi()): Record<string, string> {
  if (!status.installed || status.source === "env") return {};
  return { KIWI_LIBRARY_PATH: status.library!, KIWI_MODEL_PATH: status.model! };
}

/** Changes when the child would need a different environment. */
export const kiwiEnvKey = (status: KiwiStatus): string => (status.installed ? `${status.library}\n${status.model}` : "");

// ── install ────────────────────────────────────────────────────────────────────

export type InstallOptions = {
  dir?: string;
  platform?: NodeJS.Platform;
  arch?: string;
  /** Re-download even when this version is already installed. */
  force?: boolean;
  log?: (line: string) => void;
  fetchImpl?: typeof fetch;
  /** Test hook: a different asset table / download base. */
  assets?: { library: KiwiAsset; model: KiwiAsset; url: (asset: KiwiAsset) => string };
};

function sha256Stream(): { hash: Transform; digest: () => string } {
  const h = createHash("sha256");
  const hash = new Transform({
    transform(chunk, _enc, cb) {
      h.update(chunk as Buffer);
      cb(null, chunk);
    },
  });
  return { hash, digest: () => h.digest("hex") };
}

function fileSha256(file: string): string {
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

/** Downloads `url` to `file`, streaming, and verifies the sha256; a mismatch removes the file and throws. */
export async function downloadVerified(url: string, file: string, asset: KiwiAsset, fetchImpl: typeof fetch = fetch, log: (l: string) => void = () => {}): Promise<void> {
  if (existsSync(file) && fileSha256(file) === asset.sha256) {
    log(`${asset.name} 이미 받아 둠 (체크섬 일치)`);
    return;
  }
  mkdirSync(dirname(file), { recursive: true });
  const res = await fetchImpl(url, { headers: { "user-agent": "zaevis" }, redirect: "follow" });
  if (!res.ok || !res.body) throw new Error(`${asset.name} 다운로드 실패: HTTP ${res.status}`);
  const { hash, digest } = sha256Stream();
  let received = 0;
  let lastLogged = 0;
  const progress = new Transform({
    transform(chunk, _enc, cb) {
      received += (chunk as Buffer).length;
      if (received - lastLogged >= 20_000_000) {
        lastLogged = received;
        log(`  ${asset.name}: ${Math.round(received / 1_000_000)} / ${Math.round(asset.bytes / 1_000_000)} MB`);
      }
      cb(null, chunk);
    },
  });
  const part = `${file}.part`;
  try {
    await pipeline(Readable.fromWeb(res.body as import("node:stream/web").ReadableStream), hash, progress, createWriteStream(part));
  } catch (err) {
    rmSync(part, { force: true });
    throw err;
  }
  const got = digest();
  if (got !== asset.sha256) {
    rmSync(part, { force: true });
    throw new Error(`${asset.name} 체크섬 불일치 (기대 ${asset.sha256.slice(0, 12)}…, 실제 ${got.slice(0, 12)}…). 다시 시도하세요.`);
  }
  rmSync(file, { force: true });
  renameSync(part, file);
}

async function tarExtract(archive: string, dest: string, members: string[]): Promise<void> {
  // bsdtar (macOS, Windows 10+) and GNU tar both read .tgz and .zip with -xf and auto-detect the format.
  await new Promise<void>((res, rej) => {
    const child = spawn("tar", ["-xf", archive, "-C", dest, ...members], { stdio: ["ignore", "ignore", "pipe"] });
    let stderr = "";
    child.stderr?.on("data", (d) => (stderr += String(d)));
    child.on("error", rej);
    child.on("close", (code) => (code === 0 ? res() : rej(new Error(`tar 종료 코드 ${code}: ${stderr.trim()}`))));
  });
}

/**
 * Installs the pinned Kiwi release into `dir`: lib/<library> (static archives dropped) and
 * models/cong/base, then writes VERSION. Idempotent for the same version unless `force`.
 */
export async function installKiwi(opts: InstallOptions = {}): Promise<KiwiStatus> {
  const dir = opts.dir ?? kiwiDir();
  const platform = opts.platform ?? process.platform;
  const arch = opts.arch ?? process.arch;
  const log = opts.log ?? (() => {});
  const lib = opts.assets?.library ?? libraryAsset(platform, arch);
  if (!lib) throw new Error(`이 플랫폼(${platform}-${arch})용 Kiwi 릴리스가 없습니다. https://github.com/${KIWI_REPO}/releases 에서 직접 받아 ~/.local/kiwi/{lib,models} 에 두거나 KIWI_LIBRARY_PATH·KIWI_MODEL_PATH를 설정하세요.`);
  const model = opts.assets?.model ?? KIWI_ASSETS.model;
  const url = opts.assets?.url ?? ((a: KiwiAsset) => releaseUrl(a));
  const libraryPath = join(dir, "lib", libraryFileName(platform));
  const modelPath = join(dir, "models", "cong", "base");
  const versionFile = join(dir, "VERSION");
  const already = existsSync(libraryPath) && existsSync(modelPath) && existsSync(versionFile) && readFileSync(versionFile, "utf8").trim() === KIWI_VERSION;
  if (already && !opts.force) {
    log(`Kiwi ${KIWI_VERSION} 이미 설치됨: ${dir}`);
    return probeKiwi({ dir, platform, arch });
  }
  const downloads = join(dir, "downloads");
  mkdirSync(downloads, { recursive: true });
  log(`Kiwi ${KIWI_VERSION} 내려받는 중 (${Math.round((lib.bytes + model.bytes) / 1_000_000)} MB → ${dir})`);
  const libArchive = join(downloads, lib.name);
  const modelArchive = join(downloads, model.name);
  await downloadVerified(url(lib), libArchive, lib, opts.fetchImpl, log);
  await downloadVerified(url(model), modelArchive, model, opts.fetchImpl, log);
  log("푸는 중");
  rmSync(join(dir, "lib"), { recursive: true, force: true });
  rmSync(join(dir, "models"), { recursive: true, force: true });
  await tarExtract(libArchive, dir, ["lib"]);
  await tarExtract(modelArchive, dir, ["models"]);
  // only the dynamic library is loaded; the static archives are 50-100 MB of dead weight
  for (const f of readdirSync(join(dir, "lib"))) {
    if (/\.(a|lib|exp)$/.test(f)) rmSync(join(dir, "lib", f), { force: true });
  }
  if (!existsSync(libraryPath)) throw new Error(`푼 뒤에도 라이브러리가 없습니다: ${libraryPath}`);
  if (!existsSync(join(modelPath, "sj.morph"))) throw new Error(`푼 뒤에도 모델이 없습니다: ${modelPath}`);
  writeFileSync(versionFile, `${KIWI_VERSION}\n`);
  rmSync(downloads, { recursive: true, force: true });
  log(`설치 완료: ${libraryPath} · ${modelPath} (${Math.round(dirSize(dir) / 1_000_000)} MB)`);
  return probeKiwi({ dir, platform, arch });
}

function dirSize(dir: string): number {
  let total = 0;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isSymbolicLink()) continue;
    if (entry.isDirectory()) total += dirSize(p);
    else total += statSync(p).size;
  }
  return total;
}

export function removeKiwi(dir = kiwiDir()): void {
  rmSync(dir, { recursive: true, force: true });
}

// ── tokenizer status ───────────────────────────────────────────────────────────

export type TokenizerActive = "multilingual" | "whitespace" | "unknown";

export type TokenizerStatus = {
  /** What the current index was built with: `multilingual` (Kiwi morphemes + words) or `whitespace` only. */
  active: TokenizerActive;
  /** Kiwi is here but the index was built without it: rebuild from scratch to use it. */
  needsReindex: boolean;
  kiwi: KiwiStatus;
};

/**
 * The BM25 preset MinSync's workspace is configured with. AutoRAG writes `[lexical].language` into
 * `<workspacePath>/.autorag/minsync/.minsync/config.toml` on every refresh: `multilingual` when it found
 * Kiwi, else `simple`. Null when the index does not exist yet.
 */
export function lexicalLanguage(autoragConfigPath: string): string | null {
  try {
    const cfg = JSON.parse(readFileSync(autoragConfigPath, "utf8")) as { workspacePath?: string };
    if (!cfg.workspacePath) return null;
    const toml = readFileSync(join(cfg.workspacePath, ".autorag", "minsync", ".minsync", "config.toml"), "utf8");
    const section = toml.split(/^\[/m).find((s) => s.startsWith("lexical]"));
    const m = section?.match(/^\s*language\s*=\s*"([^"]*)"/m);
    return section ? (m?.[1] ?? "simple") : "simple";
  } catch {
    return null;
  }
}

/**
 * Keeps the search child's Kiwi environment current and remembers whether a rebuild is still owed.
 * `sync` re-probes: when Kiwi appears (or moves) it restarts the child so the next refresh uses it and
 * marks a rebuild pending; a successful `--force` refresh clears the mark. The mark persists in state.json
 * so a restart of the server does not forget it.
 */
export class TokenizerGate {
  private key: string;
  private readonly opts: { autoragConfig: string; restart: () => Promise<void>; probe?: () => KiwiStatus };
  constructor(opts: { autoragConfig: string; restart: () => Promise<void>; probe?: () => KiwiStatus }) {
    this.opts = opts;
    const status = this.probe();
    this.key = kiwiEnvKey(status);
    // an index built on whitespace (config says `simple`) while Kiwi is already here also owes a rebuild
    if (status.installed && lexicalLanguage(opts.autoragConfig) === "simple") this.setPending(true);
  }

  private probe(): KiwiStatus {
    return (this.opts.probe ?? probeKiwi)();
  }

  private setPending(v: boolean): void {
    const s = loadState();
    if ((s.kiwiReindexPending ?? false) === v) return;
    s.kiwiReindexPending = v;
    saveState(s);
  }

  /** Environment for the child; call from the child's env callback so a restart picks up the new paths. */
  env(): Record<string, string> {
    return kiwiEnv(this.probe());
  }

  /** Re-probes; restarts the child when Kiwi appeared or moved (only when `canRestart`, i.e. no refresh is running). */
  async sync(canRestart: boolean): Promise<TokenizerStatus> {
    const status = this.probe();
    const key = kiwiEnvKey(status);
    if (key !== this.key && canRestart) {
      this.key = key;
      if (status.installed) this.setPending(true);
      await this.opts.restart();
    }
    return this.status(status);
  }

  status(status: KiwiStatus = this.probe()): TokenizerStatus {
    const lang = lexicalLanguage(this.opts.autoragConfig);
    const active: TokenizerActive = lang === "multilingual" ? "multilingual" : lang === null ? (status.installed ? "unknown" : "whitespace") : "whitespace";
    const pending = loadState().kiwiReindexPending ?? false;
    return { active, needsReindex: status.installed && (pending || active === "whitespace"), kiwi: status };
  }

  /** Called when a refresh ends: a successful rebuild from scratch settles the pending mark. */
  refreshed(force: boolean, ok: boolean): void {
    if (force && ok) this.setPending(false);
  }
}
