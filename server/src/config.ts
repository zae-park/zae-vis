// Shared settings: ~/.zaevis/config.json (written by kit/setup.sh), ~/.zaevis/sources.json
// (data-source connectors) and ~/.zaevis/state.json (last collection per source).

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { normalizeAgentOrder, normalizeAgentSkip, DEFAULT_AGENT_ORDER } from "./rail.ts";
import { normalizeReportsSetting, type ReportsSetting, type ReportsState } from "./reports.ts";
import type { AgentId } from "./digest.ts";

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
  speakers: boolean; // label who spoke in transcripts after the text is saved (default on, see diarize.ts)
  transcribeSpeed: "quiet" | "fast"; // whisperX CPU use: 4 threads (default) or every core (transcribe.ts)
  hotkey: string; // global quick-capture hotkey, e.g. "meta+shift+space"; "" = the platform default
  appearance: Appearance; // the app's theme, text size and language, kept here so every window (macOS app, web) shares them
  language: string; // the language the user mostly speaks and writes ("ko"), asked on first run; the default for transcription
  transcribeLanguage: string; // "user" (follow `language`, default) | "auto" (whisper detects) | a language code
  rerank: { enabled: boolean; model: string }; // optional OpenRouter re-ranking of search results (default off)
  digest: { agent: "auto" | AgentId; model: string; weekly: boolean; daily: boolean; review: boolean; order: AgentId[]; skip: AgentId[] };
  reports: ReportsSetting; // daily / weekly / monthly reports written by the same agent (reports.ts)
  /** Folders indexed in addition to the worklog (a notebook that lives somewhere else). */
  memoryPaths: string[];
  worklogDir: string;
  reposRoot: string;
  autoragConfig: string;
  port: number;
  webDir: string;
};

type FileConfig = Partial<Omit<AppConfig, "webDir">>;

function normalizeDigest(raw: AppConfig["digest"] | undefined): AppConfig["digest"] {
  const names = ["auto", ...DEFAULT_AGENT_ORDER] as const;
  return {
    agent: names.find((a) => a === raw?.agent) ?? "auto",
    model: typeof raw?.model === "string" ? raw.model : "",
    weekly: raw?.weekly !== false,
    daily: raw?.daily !== false,
    review: raw?.review !== false,
    order: normalizeAgentOrder(raw?.order),
    skip: normalizeAgentSkip(raw?.skip),
  };
}

/** Drops the worklog itself, the home folder, and duplicates. Missing folders stay until the next save. */
function normalizeMemoryPaths(raw: unknown, worklogDir: string): string[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<string>([resolve(worklogDir), resolve(homedir()), "/"]);
  const out: string[] = [];
  for (const item of raw) {
    if (typeof item !== "string" || !item.trim()) continue;
    const abs = resolve(expandHome(item.trim()));
    if (seen.has(abs)) continue;
    seen.add(abs);
    out.push(abs);
  }
  return out.slice(0, 12);
}

export function loadConfig(): AppConfig {
  const fc = readJson<FileConfig>(join(stateDir(), "config.json"), {});
  const here = dirname(fileURLToPath(import.meta.url));
  const worklogDir = resolve(expandHome(process.env.WORKLOG_DIR ?? fc.worklogDir ?? "~/worklog"));
  return {
    dailyAt: /^\d{2}:\d{2}$/.test(String(fc.dailyAt)) ? String(fc.dailyAt) : "18:30",
    indexOnInject: fc.indexOnInject === true,
    localEmbedding: fc.localEmbedding !== false,
    notifications: fc.notifications !== false,
    speakers: fc.speakers !== false,
    transcribeSpeed: fc.transcribeSpeed === "fast" ? "fast" : "quiet",
    hotkey: typeof fc.hotkey === "string" ? fc.hotkey : "",
    appearance: normalizeAppearance(fc.appearance),
    language: normalizeLanguage(fc.language) ?? "ko",
    transcribeLanguage: fc.transcribeLanguage === "auto" ? "auto" : normalizeLanguage(fc.transcribeLanguage) ?? "user",
    rerank: { enabled: fc.rerank?.enabled === true, model: typeof fc.rerank?.model === "string" && fc.rerank.model ? fc.rerank.model : "voyageai/rerank-3-lite" },
    digest: normalizeDigest(fc.digest),
    reports: normalizeReportsSetting(fc.reports),
    memoryPaths: normalizeMemoryPaths(fc.memoryPaths, worklogDir),
    worklogDir,
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

/** A short language code ("ko", "en", "zh"), or null when [raw] is not one. */
export function normalizeLanguage(raw: unknown): string | null {
  return typeof raw === "string" && /^[a-z]{2,3}$/.test(raw.trim()) ? raw.trim() : null;
}

/** What whisperX is told: the user's language by default, nothing for "auto" (it detects from the first 30 s). */
export function transcribeLanguageFor(cfg: Pick<AppConfig, "language" | "transcribeLanguage">): string | undefined {
  if (cfg.transcribeLanguage === "auto") return undefined;
  return normalizeLanguage(cfg.transcribeLanguage) ?? cfg.language;
}

export type Appearance = { theme: "system" | "light" | "dark"; textScale: number; locale: "system" | "ko" | "en" };
/** Text sizes the app offers, as a factor of the default. */
export const TEXT_SCALES = [0.9, 1, 1.1, 1.2, 1.3];

export function normalizeAppearance(raw: unknown): Appearance {
  const a = (raw && typeof raw === "object" ? raw : {}) as { theme?: unknown; textScale?: unknown; locale?: unknown };
  const theme = a.theme === "light" || a.theme === "dark" ? a.theme : "system";
  const scale = typeof a.textScale === "number" && TEXT_SCALES.includes(a.textScale) ? a.textScale : 1;
  const locale = a.locale === "ko" || a.locale === "en" ? a.locale : "system";
  return { theme, textScale: scale, locale };
}

/** Update top-level settings in ~/.zaevis/config.json (dailyAt, indexOnInject, …). */
export function saveAppSettings(patch: Partial<Pick<AppConfig, "dailyAt" | "indexOnInject" | "localEmbedding" | "notifications" | "speakers" | "transcribeSpeed" | "hotkey" | "appearance" | "language" | "transcribeLanguage" | "rerank" | "digest" | "reports" | "memoryPaths">>): void {
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
  /** Last daily / weekly / monthly report run per kind, see reports.ts. */
  reports?: ReportsState;
  /** Kiwi arrived after the index was built: a rebuild from scratch is still owed (see kiwi.ts). */
  kiwiReindexPending?: boolean;
  /** Last sync of each external AutoRAG datasource (config key → outcome), see datasources.ts. */
  datasources?: Record<string, { lastSync: string; ok: boolean; error?: string; chunks?: number }>;
};

export const stateFile = (): string => join(stateDir(), "state.json");
export const loadState = (): CollectState => readJson<CollectState>(stateFile(), { sources: {} });
export const saveState = (s: CollectState): void => writeJson(stateFile(), s);
