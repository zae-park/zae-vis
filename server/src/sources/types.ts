// A data-source connector turns some outside activity into dated Markdown.
// The collector writes each returned day to worklog/sources/<name>/<YYYY-MM-DD>.md (overwriting it),
// so a connector must always return the *whole* day for every day it touches.

import type { AppConfig, SourceSettings } from "../config.ts";

export type CollectContext = {
  from: Date; // inclusive; the collector widens this to the start of a day
  to: Date;
  settings: SourceSettings;
  config: AppConfig;
  /** [fraction] is 0–1 while whisperX reports a percent, or null when the phase has no percent yet. */
  log: (msg: string, fraction?: number | null) => void;
  /** A quiet long step (transcription) calls this so the app can tell "still working" from "no response". */
  tick?: () => void;
};

export type CollectResult = {
  days: Record<string, string>; // "YYYY-MM-DD" → Markdown body (no title)
  note?: string;                // one-line summary for status, e.g. "전사 2건"
};

export type Source = {
  name: string;
  title: string;
  description: string;
  /** Option keys shown in the front-end settings form, with labels. */
  options: Array<{ key: string; label: string; kind: "text" | "path" | "paths" | "number" | "bool"; /** one line under the field in the app */ help?: string }>;
  /** Event-style sources (each run reports only what it just did) append to the day file instead of replacing it. */
  append?: boolean;
  collect(ctx: CollectContext): Promise<CollectResult>;
};

/** Local calendar date, the same one the user sees. */
export function dayKey(d: Date): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export function hhmm(d: Date): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${p(d.getHours())}:${p(d.getMinutes())}`;
}

export function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

export const clip = (s: string, n: number): string => {
  const one = s.replace(/\s+/g, " ").trim();
  return one.length > n ? one.slice(0, n).trimEnd() + "…" : one;
};

export function addTo(map: Record<string, string[]>, key: string, line: string): void {
  (map[key] ??= []).push(line);
}
