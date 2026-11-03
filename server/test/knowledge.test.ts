import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { knowledgeStatus, waitingDays } from "../src/knowledge.ts";

async function worklog() {
  const root = await mkdtemp(join(tmpdir(), "wl-knowledge-"));
  const put = async (rel: string, text = "x") => {
    await mkdir(join(root, rel, ".."), { recursive: true });
    await writeFile(join(root, rel), text);
  };
  await put("sources/git/2026-10-18.md");
  await put("sources/git/2026-10-20.md");
  await put("sources/agent-sessions/2026-10-20.md");
  await put("sources/shell-history/2026-11-02.md");
  await put("sources/git/notes.txt");
  await put("inbox/transcripts/2026-11-02_1703_녹음.txt");
  await put("inbox/audio/a.wav");
  await put("log/2026-10.md", "# 2026-10 로그\n\n- 10-26 [[crea]] #done a\n- 10-28 [[x]] b\n");
  await put("log/2026-11.md", "# 2026-11 로그\n\n- 11-01 [[x]] c\n");
  await put("projects/_template.md");
  await put("projects/crea.md");
  await put("summaries/2026-10.md");
  await put("reports/weekly/2026-W44.md");
  return root;
}

test("knowledge status: collected days, what waits for the next digest, review, knowledge and reports", async () => {
  const root = await worklog();
  const proposals = [
    { id: "b", createdAt: "2026-11-02T09:00:00Z", agent: "claude", status: "pending" as const, lines: 126, projects: 9, summaries: 1, processed: 3 },
    { id: "a", createdAt: "2026-10-30T09:00:00Z", agent: "claude", status: "applied" as const, lines: 3, projects: 0, summaries: 0, processed: 0 },
  ];
  const s = await knowledgeStatus(root, {
    lastDigest: "2026-10-19",
    proposals,
    collect: { lastRun: "2026-11-02T09:30:00Z", ok: true },
    reports: { daily: false, weekly: true, monthly: true },
    digest: { running: false, agent: "claude", weekly: true, nextWeekly: "2026-11-09", review: true },
  });
  assert.deepEqual(s.collect, { lastRun: "2026-11-02T09:30:00Z", ok: true, days: 4, latestDay: "2026-11-02" });
  assert.deepEqual(s.waiting, { transcripts: 1, sessions: 0, sourceDays: 2, lastDigest: "2026-10-19" }, "10-20 and 11-02 are newer than the last digest");
  assert.deepEqual(s.review.map((p) => p.id), ["b"], "only pending runs");
  assert.deepEqual(s.knowledge, { logLines: 3, latestLogDay: "2026-11-01", projects: 1, summaries: 1 });
  assert.deepEqual(s.reports, { daily: { enabled: false, count: 0 }, weekly: { enabled: true, count: 1 }, monthly: { enabled: true, count: 1 } });

  const fresh = await knowledgeStatus(await mkdtemp(join(tmpdir(), "wl-empty-")), {
    lastDigest: null,
    proposals: [],
    collect: null,
    reports: { daily: false, weekly: false, monthly: false },
    digest: { running: false, agent: null, weekly: true, nextWeekly: null, review: true },
  });
  assert.deepEqual(fresh.collect, { lastRun: null, ok: null, days: 0, latestDay: null }, "an empty worklog is not an error");
  assert.equal(fresh.knowledge.logLines, 0);
});

test("waitingDays counts whole days since a proposal was made", () => {
  assert.equal(waitingDays("2026-11-02T09:00:00Z", new Date("2026-11-03T08:00:00Z")), 0);
  assert.equal(waitingDays("2026-11-02T09:00:00Z", new Date("2026-11-05T10:00:00Z")), 3);
});
