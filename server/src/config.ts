// Shared settings: ~/.zaevis/config.json (written by kit/setup.sh), ~/.zaevis/sources.json
// (data-source connectors) and ~/.zaevis/state.json (last collection per source).

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const stateDir = (): string => process.env.ZAEVIS_HOME ?? join(homedir(), ".zaevis");

export const expandHome = (p: string): string => (p === "~" ? homedir() : p.startsWith("~/") ? join(homedir(), p.slice(2)) : p);

function readJson<T>(file: string, fallback: T): T {
  if (!existsSync(file)) return fallback;
  try {
    return JSON.parse(readFileSync(file, "utf8")) as T;
  } catch (err) {
    throw new Error(`${file} 을(를) 읽을 수 없습니다: ${(err as Error).message}`);
  }
}

export function writeJson(file: string, value: unknown): void {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(value, null, 2) + "\n");
}

export type AppConfig = {
  dailyAt: string;        // "18:30" — daily collect + index (launchd)
  indexOnInject: boolean; // re-index right after a log line / transcript is added
  localEmbedding: boolean; // keep a local `minsync serve` embedding daemon for semantic search (default on)
  notifications: boolean; // OS notifications for digest / collect / transcription results (default on)
  hotkey: string; // global quick-capture hotkey, e.g. "meta+shift+space"; "" = the platform default
  rerank: { enabled: boolean; model: string }; // optional OpenRouter re-ranking of search results (default off)
  digest: { agent: "auto" | "claude" | "codex" | "gemini" | "openrouter"; model: string; weekly: boolean; review: boolean }; // weekly digest runner
  worklogDir: string;
  reposRoot: string;
  autoragConfig: string;
  port: number;
  webDir: string;
};

type FileConfig = Partial<Omit<AppConfig, "webDir">>;

export function loadConfig(): AppConfig {
  const fc = readJson<FileConfig>(join(stateDir(), "config.json"), {});
  const here = dirname(fileURLToPath(import.meta.url));
  return {
    dailyAt: /^\d{2}:\d{2}$/.test(String(fc.dailyAt)) ? String(fc.dailyAt) : "18:30",
    indexOnInject: fc.indexOnInject === true,
    localEmbedding: fc.localEmbedding !== false,
    notifications: fc.notifications !== false,
    hotkey: typeof fc.hotkey === "string" ? fc.hotkey : "",
    rerank: { enabled: fc.rerank?.enabled === true, model: typeof fc.rerank?.model === "string" && fc.rerank.model ? fc.rerank.model : "voyageai/rerank-3-lite" },
    digest: {
      agent: (["auto", "claude", "codex", "gemini", "openrouter"] as const).find((a) => a === fc.digest?.agent) ?? "auto",
      model: typeof fc.digest?.model === "string" ? fc.digest.model : "",
      weekly: fc.digest?.weekly !== false,
      review: fc.digest?.review !== false,
    },
    worklogDir: resolve(expandHome(process.env.WORKLOG_DIR ?? fc.worklogDir ?? "~/worklog")),
    reposRoot: resolve(expandHome(fc.reposRoot ?? "~")),
    autoragConfig: expandHome(process.env.AUTORAG_CONFIG ?? fc.autoragConfig ?? join(stateDir(), "autorag", "config.json")),
    port: Number(process.env.ZAEVIS_PORT ?? fc.port ?? 4710),
    // may not exist yet; built later by `zaevis run web`
    // packaged app: <payload>/web · repo checkout: app/build/web (may not exist until built)
    webDir: process.env.ZAEVIS_WEB_DIR ?? (existsSync(resolve(here, "..", "..", "web", "index.html")) ? resolve(here, "..", "..", "web") : resolve(here, "..", "..", "app", "build", "web")),
  };
}

// ── data sources ──────────────────────────────────────────────────────────────

export type SourceSettings = { enabled: boolean; [key: string]: unknown };
export type CustomSource = { name: string; command: string; enabled?: boolean; description?: string };
export type SourcesConfig = Record<string, SourceSettings> & { custom?: CustomSource[] };

export const sourcesFile = (): string => join(stateDir(), "sources.json");

/** Built-in defaults; ~/.zaevis/sources.json overrides per key. */
export function defaultSources(cfg: AppConfig): SourcesConfig {
  return {
    git: { enabled: true, reposRoot: cfg.reposRoot, depth: 3 },
    "agent-sessions": { enabled: true, claude: true, codex: true, gemini: true, chatgptExportDir: "" },
    "shell-history": { enabled: true, historyFile: "~/.zsh_history" },
    transcripts: {
      enabled: true,
      audioDir: join(cfg.worklogDir, "inbox", "audio"),
      importDirs: [],
      language: "ko",
      model: "large-v3-turbo",
    },
  } as SourcesConfig;
}

export function loadSources(cfg: AppConfig): SourcesConfig {
  const user = readJson<Partial<SourcesConfig>>(sourcesFile(), {});
  const merged = defaultSources(cfg) as Record<string, unknown>;
  for (const [k, v] of Object.entries(user)) {
    if (k === "custom") continue;
    const base = (merged[k] ?? {}) as Record<string, unknown>;
    merged[k] = { ...base, ...(v as Record<string, unknown>) };
  }
  merged.custom = Array.isArray(user.custom) ? user.custom : [];
  return merged as SourcesConfig;
}

/** Merge `patch` into one source's settings in ~/.zaevis/sources.json (built-in or custom). */
export function saveSourceSettings(name: string, patch: Record<string, unknown>): void {
  const user = readJson<Record<string, any>>(sourcesFile(), {});
  const custom = Array.isArray(user.custom) ? (user.custom as CustomSource[]) : [];
  const c = custom.find((x) => x.name === name);
  if (c) Object.assign(c, patch);
  else user[name] = { ...(user[name] ?? {}), ...patch };
  user.custom = custom;
  writeJson(sourcesFile(), user);
}

export function addCustomSource(src: CustomSource): void {
  const user = readJson<Record<string, any>>(sourcesFile(), {});
  const custom = Array.isArray(user.custom) ? (user.custom as CustomSource[]) : [];
  if (custom.some((x) => x.name === src.name)) throw new Error(`이미 있는 이름입니다: ${src.name}`);
  custom.push({ enabled: true, ...src });
  user.custom = custom;
  writeJson(sourcesFile(), user);
}

export function removeCustomSource(name: string): boolean {
  const user = readJson<Record<string, any>>(sourcesFile(), {});
  const custom = Array.isArray(user.custom) ? (user.custom as CustomSource[]) : [];
  const next = custom.filter((x) => x.name !== name);
  if (next.length === custom.length) return false;
  user.custom = next;
  writeJson(sourcesFile(), user);
  return true;
}

/** Update top-level settings in ~/.zaevis/config.json (dailyAt, indexOnInject, …). */
export function saveAppSettings(patch: Partial<Pick<AppConfig, "dailyAt" | "indexOnInject" | "localEmbedding" | "notifications" | "hotkey" | "rerank" | "digest">>): void {
  const file = join(stateDir(), "config.json");
  writeJson(file, { ...readJson<Record<string, unknown>>(file, {}), ...patch });
}

export type SourceState = { lastRun?: string; lastOk?: boolean; lastError?: string; lastErrorAt?: string; lastNote?: string };
export type CollectState = {
  sources: Record<string, SourceState>;
  daily?: { lastRun: string; ok: boolean; index: string };
  /** Vectors were built from scratch for this embedding model (so a first start re-indexes once). */
  embedding?: { model: string; builtAt: string };
  /** Last weekly digest run. */
  digest?: { lastRun: string; agent: string; ok: boolean; report: string };
  /** Last sync of each external AutoRAG datasource (config key → outcome), see datasources.ts. */
  datasources?: Record<string, { lastSync: string; ok: boolean; error?: string; chunks?: number }>;
};

export const stateFile = (): string => join(stateDir(), "state.json");
export const loadState = (): CollectState => readJson<CollectState>(stateFile(), { sources: {} });
export const saveState = (s: CollectState): void => writeJson(stateFile(), s);
