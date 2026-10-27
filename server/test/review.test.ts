import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rename, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

process.env.ZAEVIS_HOME = await mkdtemp(join(tmpdir(), "zv-review-state-"));
const { applyProposal, diffSnapshot, isEmptyProposal, listProposals, loadProposal, newProposalId, restoreSnapshot, saveProposal, takeSnapshot } = await import("../src/review.ts");

async function worklog(): Promise<string> {
  const w = await mkdtemp(join(tmpdir(), "zv-review-wl-"));
  await mkdir(join(w, "log"), { recursive: true });
  await mkdir(join(w, "projects"), { recursive: true });
  await mkdir(join(w, "inbox", "transcripts"), { recursive: true });
  await writeFile(join(w, "log", "2026-10.md"), "# 2026-10 로그\n\n- 10-01 [[a]] #done 내 줄\n");
  await writeFile(join(w, "projects", "a.md"), "# A\n\n## 현재 상태\n\n예전\n");
  await writeFile(join(w, "inbox", "transcripts", "2026-10-20_회의.txt"), "회의 내용\n");
  await writeFile(join(w, ".state.md"), "last_weekly: 2026-10-19\n");
  return w;
}

/** What an agent run typically does to the folder. */
async function simulateAgent(w: string): Promise<void> {
  await writeFile(join(w, "log", "2026-10.md"), "# 2026-10 로그\n\n- 10-01 [[a]] #done 내 줄\n- 10-20 [[a]] #decision 회의에서 정함 (src: 2026-10-20_회의)\n- 10-21 [[b]] #done 새 프로젝트 시작 (src: git b 1234567)\n");
  await writeFile(join(w, "projects", "a.md"), "# A\n\n## 현재 상태\n\n새 상태\n");
  await writeFile(join(w, "projects", "b.md"), "# B\n\n## 현재 상태\n\n시작\n");
  await mkdir(join(w, "processed", "transcripts"), { recursive: true });
  await rename(join(w, "inbox", "transcripts", "2026-10-20_회의.txt"), join(w, "processed", "transcripts", "2026-10-20_회의.txt"));
  await mkdir(join(w, "summaries"), { recursive: true });
  await writeFile(join(w, "summaries", "2026-09.md"), "# 2026-09 작업 정리\n");
  await writeFile(join(w, ".state.md"), "last_weekly: 2026-10-26\n");
}

test("review: snapshot → agent changes → diff is a proposal → restore puts everything back", async () => {
  const w = await worklog();
  const before = await takeSnapshot(w);
  assert.deepEqual(before.inbox, ["inbox/transcripts/2026-10-20_회의.txt"]);
  await simulateAgent(w);
  const d = await diffSnapshot(w, before);
  assert.equal(isEmptyProposal(d), false);
  assert.deepEqual(d.logLines.map((l) => [l.month, l.entry.date, l.entry.projects[0], l.entry.source]), [["2026-10", "10-20", "a", "2026-10-20_회의"], ["2026-10", "10-21", "b", "git b 1234567"]]);
  assert.deepEqual(d.removedLines, []);
  assert.deepEqual(d.projects.map((p) => [p.slug, p.before === null]), [["a", false], ["b", true]]);
  assert.deepEqual(d.summaries.map((s) => s.path), ["summaries/2026-09.md"]);
  assert.deepEqual(d.processed, [{ from: "inbox/transcripts/2026-10-20_회의.txt", to: "processed/transcripts/2026-10-20_회의.txt" }]);
  assert.equal(d.stateAfter, "last_weekly: 2026-10-26\n");

  await restoreSnapshot(w, before);
  assert.equal(await readFile(join(w, "log", "2026-10.md"), "utf8"), "# 2026-10 로그\n\n- 10-01 [[a]] #done 내 줄\n");
  assert.equal(await readFile(join(w, "projects", "a.md"), "utf8"), "# A\n\n## 현재 상태\n\n예전\n");
  assert.equal(existsSync(join(w, "projects", "b.md")), false, "file the run created is removed");
  assert.equal(existsSync(join(w, "summaries", "2026-09.md")), false);
  assert.equal(existsSync(join(w, "inbox", "transcripts", "2026-10-20_회의.txt")), true, "inbox file moved back");
  assert.equal(await readFile(join(w, ".state.md"), "utf8"), "last_weekly: 2026-10-19\n");
  assert.equal(isEmptyProposal(await diffSnapshot(w, before)), true, "nothing differs after restore");
});

test("review: a removed user line shows up as removedLines, never silently", async () => {
  const w = await worklog();
  const before = await takeSnapshot(w);
  await writeFile(join(w, "log", "2026-10.md"), "# 2026-10 로그\n\n- 10-02 [[a]] #done 바꿔치기\n");
  const d = await diffSnapshot(w, before);
  assert.equal(d.removedLines[0].entry.text, "내 줄");
  assert.equal(d.logLines[0].entry.text, "바꿔치기");
});

test("review: apply writes only the selected parts; proposals are stored and listed", async () => {
  const w = await worklog();
  const before = await takeSnapshot(w);
  await simulateAgent(w);
  const d = await diffSnapshot(w, before);
  await restoreSnapshot(w, before);
  const id = newProposalId(new Date("2026-10-27T10:00:00Z"));
  assert.equal(id, "20261027-100000");
  await saveProposal({ id, createdAt: "2026-10-27T10:00:00Z", agent: "claude", report: "r", status: "pending", ...d });
  const listed = await listProposals();
  assert.deepEqual(listed.map((p) => [p.id, p.status, p.lines, p.projects, p.processed, p.summaries]), [[id, "pending", 2, 2, 1, 1]]);

  const p = (await loadProposal(id))!;
  const applied = await applyProposal(w, p, { lines: [1], projects: ["b"], summaries: false, processed: true });
  assert.deepEqual(applied, { lines: 1, projects: ["b"], summaries: 0, processed: 1 });
  const log = await readFile(join(w, "log", "2026-10.md"), "utf8");
  assert.match(log, /- 10-01 \[\[a\]\] #done 내 줄\n- 10-21 \[\[b\]\] #done 새 프로젝트 시작/, "my line kept, chosen line appended");
  assert.doesNotMatch(log, /회의에서 정함/, "unchecked line not written");
  assert.equal(await readFile(join(w, "projects", "a.md"), "utf8"), "# A\n\n## 현재 상태\n\n예전\n", "unchecked project untouched");
  assert.equal(await readFile(join(w, "projects", "b.md"), "utf8"), "# B\n\n## 현재 상태\n\n시작\n");
  assert.equal(existsSync(join(w, "summaries", "2026-09.md")), false);
  assert.equal(existsSync(join(w, "processed", "transcripts", "2026-10-20_회의.txt")), true);
  assert.equal(await readFile(join(w, ".state.md"), "utf8"), "last_weekly: 2026-10-26\n", "state advances once a proposal is applied");

  assert.equal(await loadProposal("../etc"), null, "ids are validated");
  await rm(w, { recursive: true, force: true });
});
