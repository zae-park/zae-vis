// "지식화 현황": where the user's material is on its way from collection to knowledge, in one answer
// (GET /api/knowledge). The app turns it into a five-step strip and the one next thing to do; the steps are
// the worklog's own: sources/ (collected) → inbox/ + sources since the last digest (waiting) → proposals
// (waiting for review) → log/ projects/ summaries/ (knowledge) → reports/.

import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import type { ProposalSummary } from "./review.ts";

export type KnowledgeStatus = {
  collect: { lastRun: string | null; ok: boolean | null; days: number; latestDay: string | null };
  /** Material the next digest reads: inbox files, and source days newer than the last digest (daily or weekly). */
  waiting: { transcripts: number; sessions: number; sourceDays: number; lastDigest: string | null };
  /** Digest runs left for the user to approve, oldest first. */
  review: ProposalSummary[];
  knowledge: { logLines: number; latestLogDay: string | null; projects: number; summaries: number };
  reports: { daily: { enabled: boolean; count: number }; weekly: { enabled: boolean; count: number }; monthly: { enabled: boolean; count: number } };
  digest: { running: boolean; agent: string | null; weekly: boolean; daily?: boolean; nextWeekly: string | null; review: boolean };
};

const DAY = /^(\d{4}-\d{2}-\d{2})\.md$/;

async function names(dir: string): Promise<string[]> {
  try {
    return (await readdir(dir)).filter((n) => !n.startsWith("."));
  } catch {
    return [];
  }
}

/** Collected day files under sources/<name>/YYYY-MM-DD.md: how many, the distinct dates, the newest. */
export async function sourceDays(root: string): Promise<{ files: number; dates: Set<string> }> {
  const dates = new Set<string>();
  let files = 0;
  for (const src of await names(join(root, "sources"))) {
    for (const n of await names(join(root, "sources", src))) {
      const m = DAY.exec(n);
      if (!m) continue;
      files++;
      dates.add(m[1]);
    }
  }
  return { files, dates };
}

/** Log lines ("- 10-26 …") across log/YYYY-MM.md and the date of the newest. */
export async function logLines(root: string): Promise<{ count: number; latest: string | null }> {
  let count = 0;
  let latest: string | null = null;
  for (const n of (await names(join(root, "log"))).filter((x) => /^\d{4}-\d{2}\.md$/.test(x)).sort()) {
    const text = await readFile(join(root, "log", n), "utf8").catch(() => "");
    for (const line of text.split("\n")) {
      const m = /^- (\d{2})-(\d{2}) /.exec(line);
      if (!m) continue;
      count++;
      const day = `${n.slice(0, 4)}-${m[1]}-${m[2]}`;
      if (!latest || day > latest) latest = day;
    }
  }
  return { count, latest };
}

export async function knowledgeStatus(
  root: string,
  deps: {
    lastDigest: string | null;
    proposals: ProposalSummary[];
    collect: { lastRun: string; ok: boolean } | null;
    reports: { daily: boolean; weekly: boolean; monthly: boolean };
    digest: { running: boolean; agent: string | null; weekly: boolean; daily?: boolean; nextWeekly: string | null; review: boolean };
  },
): Promise<KnowledgeStatus> {
  const days = await sourceDays(root);
  const sorted = [...days.dates].sort();
  const log = await logLines(root);
  const md = (xs: string[]) => xs.filter((n) => n.endsWith(".md"));
  const projects = md(await names(join(root, "projects"))).filter((n) => !n.startsWith("_"));
  const summaries = md(await names(join(root, "summaries")));
  const count = async (dir: string) => md(await names(join(root, "reports", dir))).length;
  const inbox = async (dir: string) => (await names(join(root, "inbox", dir))).filter((n) => /\.(md|txt)$/i.test(n)).length;
  return {
    collect: { lastRun: deps.collect?.lastRun ?? null, ok: deps.collect?.ok ?? null, days: days.files, latestDay: sorted.at(-1) ?? null },
    waiting: {
      transcripts: await inbox("transcripts"),
      sessions: await inbox("claude-sessions"),
      sourceDays: deps.lastDigest ? sorted.filter((d) => d > deps.lastDigest!).length : sorted.length,
      lastDigest: deps.lastDigest,
    },
    review: deps.proposals.filter((p) => p.status === "pending").sort((a, b) => a.createdAt.localeCompare(b.createdAt)),
    knowledge: { logLines: log.count, latestLogDay: log.latest, projects: projects.length, summaries: summaries.length },
    reports: {
      daily: { enabled: deps.reports.daily, count: await count("daily") },
      weekly: { enabled: deps.reports.weekly, count: await count("weekly") },
      monthly: { enabled: deps.reports.monthly, count: summaries.length },
    },
    digest: deps.digest,
  };
}

/** Days a pending proposal has waited, for the reminder (daily.ts) and the app's line. */
export const waitingDays = (createdAt: string, now = new Date()): number => Math.floor((now.getTime() - new Date(createdAt).getTime()) / 86_400_000);
