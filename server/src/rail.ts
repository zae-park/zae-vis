// Which subscribed CLI (or, last, the OpenRouter key) a question, report or digest will try, and what
// happened to each one. "auto" walks the usable ones in detectAgents order and, on a quota error only,
// tries the next. A pinned agent is the only stop that runs. The app draws this list as a rail.

import type { AgentId, AgentInfo, DigestSetting } from "./digest.ts";

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

const QUOTA = /rate[\s-]?limit|usage limit|\bquota\b|insufficient_quota|\b429\b|http 402|\b402\b|too many requests|resource_exhausted|hit your (usage |rate )?limit|out of (credits|extra usage)|credit balance|spending cap|exceeded your|extra usage/i;

/** The CLI's own line when `text` is a quota or rate-limit failure, else null. Login and timeout are not quota. */
export function quotaReason(text: string): string | null {
  const flat = text.replace(/\r/g, "");
  if (!QUOTA.test(flat)) return null;
  const line = flat.split("\n").map((s) => s.trim()).filter(Boolean).reverse().find((s) => QUOTA.test(s)) ?? flat.trim();
  return line.replace(/\s+/g, " ").slice(0, 80);
}

/** Who a run will actually call, in order. Pinned → that one agent. Auto → every usable agent. */
export function fallbackCandidates(setting: Pick<DigestSetting, "agent">, agents: AgentInfo[]): AgentInfo[] {
  if (setting.agent !== "auto") {
    const one = agents.find((a) => a.id === setting.agent && usable(a));
    return one ? [one] : [];
  }
  return agents.filter(usable);
}

/** The rail before anything runs: installed-but-signed-out and missing tools stay visible, dimmed. */
export function plannedRail(setting: Pick<DigestSetting, "agent">, agents: AgentInfo[]): RailStop[] {
  const pinned = setting.agent !== "auto";
  const willTry = new Set(fallbackCandidates(setting, agents).map((a) => a.id));
  return agents.map((a) => {
    const metered = a.id === "openrouter";
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
