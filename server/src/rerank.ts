// Optional search re-ranking through OpenRouter — the only external model AutoRAG Lite can use.
// Off by default: nothing leaves this machine unless the user turns it on and saves a key here.
//
// - key:      $ZAEVIS_HOME/secrets.json (mode 0600), never returned by the API, only its last 4 chars
// - setting:  $ZAEVIS_HOME/config.json → rerank: { enabled, model }
// - effect:   $ZAEVIS_HOME/autorag/config.json → rerank: { provider: "openrouter", … } or false,
//             and OPENROUTER_API_KEY in the environment of the autorag-mcp child process.
//
// (AutoRAG's Lite search also carries jev / queryDecomposition settings in that file; Lite never
// uses them, so they are removed to keep the file honest.)

import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { stateDir } from "./config.ts";

export const RERANK_KEY_ENV = "OPENROUTER_API_KEY";
export const DEFAULT_RERANK_MODEL = "voyageai/rerank-3-lite";
const RERANK_TOP_N = 25;
const OPENROUTER_KEY_URL = "https://openrouter.ai/api/v1/auth/key";

export type RerankSetting = { enabled: boolean; model: string };

export type RerankStatus = RerankSetting & {
  hasKey: boolean;
  /** Last 4 characters of the stored key, for "•••• ab12" in the UI. */
  keyHint: string | null;
  /** Plain-language summary of what leaves the machine. */
  external: string;
};

// ── secrets ────────────────────────────────────────────────────────────────────

export const secretsFile = (): string => join(stateDir(), "secrets.json");

function readSecrets(): Record<string, string> {
  const f = secretsFile();
  if (!existsSync(f)) return {};
  try {
    const v = JSON.parse(readFileSync(f, "utf8")) as unknown;
    return v && typeof v === "object" ? (v as Record<string, string>) : {};
  } catch {
    return {};
  }
}

function writeSecrets(s: Record<string, string>): void {
  const f = secretsFile();
  mkdirSync(dirname(f), { recursive: true });
  writeFileSync(f, JSON.stringify(s, null, 2) + "\n", { mode: 0o600 });
  chmodSync(f, 0o600); // writeFileSync's mode only applies when the file is created
}

/** Secrets stored under "env:<NAME>" — token values external connectors need (see datasources.ts). */
export function getEnvSecret(name: string): string | null {
  const v = readSecrets()[`env:${name}`];
  return typeof v === "string" && v.trim() ? v.trim() : null;
}

export function setEnvSecret(name: string, value: string): void {
  const s = readSecrets();
  if (value.trim()) s[`env:${name}`] = value.trim();
  else delete s[`env:${name}`];
  writeSecrets(s);
}

export function allEnvSecrets(): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(readSecrets())) if (k.startsWith("env:") && typeof v === "string" && v.trim()) out[k.slice(4)] = v.trim();
  return out;
}

export function getKey(): string | null {
  const k = readSecrets().openrouter;
  return typeof k === "string" && k.trim() ? k.trim() : null;
}

export function setKey(key: string | null): void {
  const s = readSecrets();
  if (key && key.trim()) s.openrouter = key.trim();
  else delete s.openrouter;
  writeSecrets(s);
}

export const keyHint = (key: string | null): string | null => (key && key.length >= 4 ? key.slice(-4) : null);

// ── AutoRAG config ─────────────────────────────────────────────────────────────

/**
 * Rewrites the rerank section of AutoRAG's config file. `enabled` with a key → OpenRouter reranker;
 * otherwise `rerank: false`. Model-only settings Lite never uses (jev, queryDecomposition) are dropped.
 */
export function applyToAutoragConfig(autoragConfig: string, setting: RerankSetting, hasKey: boolean): boolean {
  if (!existsSync(autoragConfig)) return false;
  const cfg = JSON.parse(readFileSync(autoragConfig, "utf8")) as Record<string, unknown>;
  delete cfg.jev;
  delete cfg.queryDecomposition;
  cfg.rerank = setting.enabled && hasKey ? { provider: "openrouter", model: setting.model || DEFAULT_RERANK_MODEL, apiKeyEnv: RERANK_KEY_ENV, topN: RERANK_TOP_N } : false;
  writeFileSync(autoragConfig, JSON.stringify(cfg, null, 2) + "\n");
  return true;
}

/** Environment the autorag-mcp child gets: the key only while re-ranking is on. */
export function childEnv(setting: RerankSetting): Record<string, string> {
  const key = setting.enabled ? getKey() : null;
  return key ? { [RERANK_KEY_ENV]: key } : {};
}

export function status(setting: RerankSetting): RerankStatus {
  const key = getKey();
  const on = setting.enabled && key !== null;
  return {
    ...setting,
    model: setting.model || DEFAULT_RERANK_MODEL,
    hasKey: key !== null,
    keyHint: keyHint(key),
    external: on ? `검색어와 상위 ${RERANK_TOP_N}개 문단이 OpenRouter(${setting.model || DEFAULT_RERANK_MODEL})로 전송됩니다.` : "없음 — 모든 검색은 이 맥 안에서 처리됩니다.",
  };
}

// ── key check ──────────────────────────────────────────────────────────────────

export type KeyCheck = { ok: boolean; message: string };

/** Asks OpenRouter whether the key is valid. Never includes the key in the result. */
export async function testKey(key: string, fetchImpl: typeof fetch = fetch): Promise<KeyCheck> {
  if (!key.trim()) return { ok: false, message: "키가 비어 있습니다." };
  try {
    const res = await fetchImpl(OPENROUTER_KEY_URL, { headers: { authorization: `Bearer ${key.trim()}` }, signal: AbortSignal.timeout(10_000) });
    if (res.status === 401 || res.status === 403) return { ok: false, message: "OpenRouter가 이 키를 거부했습니다 (401). 키를 다시 확인하세요." };
    if (!res.ok) return { ok: false, message: `OpenRouter 응답 오류 (HTTP ${res.status}).` };
    const body = (await res.json().catch(() => ({}))) as { data?: { label?: string; limit?: number | null; usage?: number } };
    const label = body.data?.label ? ` (${body.data.label})` : "";
    return { ok: true, message: `연결됨${label}.` };
  } catch (err) {
    return { ok: false, message: `OpenRouter에 연결하지 못했습니다: ${(err as Error).message}` };
  }
}
