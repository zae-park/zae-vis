// Which subscribed CLI (or, last, the OpenRouter key) a question, report or digest will try, and what
// happened to each one. "auto" walks the usable ones in the user's order and, on a quota error only,
// tries the next. A pinned agent is the only stop that runs. The app draws this list as a rail.
//
// Default order: Claude, Codex, Cursor, Gemini, then OpenRouter. `digest.order` is that list after
// the user drags the blocks; `digest.skip` drops a block without forgetting its place.

import type { AgentId, AgentInfo, DigestSetting } from "./digest.ts";

export const DEFAULT_AGENT_ORDER: readonly AgentId[] = ["claude", "codex", "cursor", "gemini", "openrouter"];

const KNOWN = new Set<string>(DEFAULT_AGENT_ORDER);

/** Known ids in the saved order, then any default that was missing. */
export function normalizeAgentOrder(raw: unknown): AgentId[] {
  const seen = new Set<AgentId>();
  const out: AgentId[] = [];
  if (Array.isArray(raw)) {
    for (const id of raw) {
      if (typeof id !== "string" || !KNOWN.has(id) || seen.has(id as AgentId)) continue;
      seen.add(id as AgentId);
      out.push(id as AgentId);
    }
  }
  for (const id of DEFAULT_AGENT_ORDER) if (!seen.has(id)) out.push(id);
  return out;
}

/** Ids the user turned off. Unknown names are dropped. */
export function normalizeAgentSkip(raw: unknown): AgentId[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<AgentId>();
  const out: AgentId[] = [];
  for (const id of raw) {
    if (typeof id !== "string" || !KNOWN.has(id) || seen.has(id as AgentId)) continue;
    seen.add(id as AgentId);
    out.push(id as AgentId);
  }
  return out;
}

/** Detected agents in the fallback order, including ones that are off or signed out. */
export function agentsInOrder(setting: Pick<DigestSetting, "order">, agents: AgentInfo[]): AgentInfo[] {
  const order = normalizeAgentOrder(setting.order);
  const byId = new Map(agents.map((a) => [a.id, a]));
  const out: AgentInfo[] = [];
  for (const id of order) {
    const a = byId.get(id);
    if (a) out.push(a);
  }
  for (const a of agents) if (!order.includes(a.id)) out.push(a);
  return out;
}

/** Installed and not known to be signed out. Same rule as digest.usable, kept here to avoid a cycle. */
const usable = (a: AgentInfo): boolean => a.available && a.loggedIn !== false;

export type RailState = "off" | "login" | "ready" | "running" | "quota" | "wrote" | "error";

export type RailStop = {
  id: AgentId;
  title: string;
  /** OpenRouter is metered, not a local subscription. The rail labels it so. */
  metered: boolean;
  state: RailState;
  /** The CLI's own last line when the stop was skipped or failed. */
  reason?: string;
};

const QUOTA = /rate[\s-]?limit|usage limit|session limit|weekly limit|\bquota\b|insufficient_quota|\b429\b|http 402|\b402\b|too many requests|resource_exhausted|hit your(?: [\w-]+){0,3} limit|out of (credits|extra usage)|credit balance|spending cap|exceeded your|extra usage/i;

/** The CLI's own line when `text` is a quota or rate-limit failure, else null. Login and timeout are not quota. */
export function quotaReason(text: string): string | null {
  const flat = text.replace(/\r/g, "");
  if (!QUOTA.test(flat)) return null;
  const line = flat.split("\n").map((s) => s.trim()).filter(Boolean).reverse().find((s) => QUOTA.test(s)) ?? flat.trim();
  return line.replace(/\s+/g, " ").slice(0, 80);
}

/**
 * Claude exits 0 and prints "You've hit your weekly limit · resets …" as the whole answer.
 * A real answer is longer or cites [n], so that text is left alone. A non-zero exit is quota
 * whenever the output matches, whatever its length.
 */
export function replyQuota(stdout: string, stderr: string, ok: boolean): string | null {
  if (!ok) return quotaReason(`${stderr}\n${stdout}`);
  const body = stdout.trim();
  if (!body || body.length > 240 || /\[\d+\]/.test(body)) return null;
  return quotaReason(body);
}

/** Who a run will actually call, in the user's order. Pinned → that one agent. Auto → every usable agent not skipped. */
export function fallbackCandidates(setting: Pick<DigestSetting, "agent" | "order" | "skip">, agents: AgentInfo[]): AgentInfo[] {
  const skip = new Set(setting.skip ?? []);
  const list = agentsInOrder(setting, agents).filter((a) => !skip.has(a.id));
  if (setting.agent !== "auto") {
    const one = list.find((a) => a.id === setting.agent && usable(a));
    return one ? [one] : [];
  }
  return list.filter(usable);
}

/** The rail before anything runs: installed-but-signed-out and missing tools stay visible, dimmed. */
export function plannedRail(setting: Pick<DigestSetting, "agent" | "order" | "skip">, agents: AgentInfo[]): RailStop[] {
  const pinned = setting.agent !== "auto";
  const skip = new Set(setting.skip ?? []);
  const willTry = new Set(fallbackCandidates(setting, agents).map((a) => a.id));
  return agentsInOrder(setting, agents).map((a) => {
    const metered = a.id === "openrouter";
    if (skip.has(a.id)) return { id: a.id, title: a.title, metered, state: "off", reason: "이 순서에서 빼 두었습니다" };
    if (!a.available) return { id: a.id, title: a.title, metered, state: "off", reason: a.detail };
    if (a.loggedIn === false) return { id: a.id, title: a.title, metered, state: "login", reason: a.loginHint ?? "로그인 필요" };
    if (!willTry.has(a.id)) return { id: a.id, title: a.title, metered, state: "off", reason: pinned ? "다른 서비스를 고정해 두었습니다" : a.detail };
    return { id: a.id, title: a.title, metered, state: "ready" };
  });
}

/** A copy of the rail with one stop moved to `state`. */
export function withStop(rail: RailStop[], id: AgentId, state: RailState, reason?: string): RailStop[] {
  return rail.map((s) => (s.id === id ? { ...s, state, ...(reason !== undefined ? { reason } : state === "running" ? { reason: undefined } : {}) } : s));
}
