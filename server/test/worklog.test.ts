import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseFrontMatter, parseLog, parseLogLine, parseProject, Worklog } from "../src/worklog.ts";

test("parseLogLine: user-written line", () => {
  const e = parseLogLine("- 10-07 [[hiring]] #decision DS JD에 실험설계 역량을 필수로 추가");
  assert.deepEqual(e, {
    date: "10-07",
    projects: ["hiring"],
    tags: ["decision"],
    text: "DS JD에 실험설계 역량을 필수로 추가",
    source: null,
    author: "me",
    raw: "- 10-07 [[hiring]] #decision DS JD에 실험설계 역량을 필수로 추가",
  });
});

test("parseLogLine: Claude-written line keeps source and multiple links", () => {
  const e = parseLogLine("- 10-08 [[roas-multihorizon]] [[ltv]] #done 광고·결제 분리 채점 (src: git roas-multihorizon a1b2c3d)");
  assert.ok(e);
  assert.deepEqual(e.projects, ["roas-multihorizon", "ltv"]);
  assert.equal(e.source, "git roas-multihorizon a1b2c3d");
  assert.equal(e.author, "claude");
  assert.equal(e.text, "광고·결제 분리 채점");
});

test("parseLogLine: ignores headings, blank lines and C# in text is not split oddly", () => {
  assert.equal(parseLogLine("# 2026-10 로그"), null);
  assert.equal(parseLogLine(""), null);
  const e = parseLogLine("- 10-09 #learned 이슈 #123 은 태그로 본다");
  assert.ok(e);
  assert.deepEqual(e.tags, ["learned", "123"]);
});

test("parseLog skips non-entry lines", () => {
  const md = "# 2026-10 로그\n\n- 10-06 [[a]] #done x\n메모\n* 10-07 #blocked y\n";
  assert.deepEqual(parseLog(md).map((e) => e.date), ["10-06", "10-07"]);
});

test("parseFrontMatter reads scalars and lists, strips comments", () => {
  const { meta, body } = parseFrontMatter("---\nrepos: [a, b]     # 저장소\nstatus: 진행 중\n---\n# T\n");
  assert.deepEqual(meta, { repos: ["a", "b"], status: "진행 중" });
  assert.equal(body, "# T\n");
});

test("parseProject pulls title and 현재 상태", () => {
  const p = parseProject("x", "---\nrepos: [r]\nstatus: 보류\n---\n# 프로젝트 X\n\n## 현재 상태\n둘째 줄\n\n## 주요 결정\n- d\n");
  assert.deepEqual(p, { slug: "x", title: "프로젝트 X", status: "보류", repos: ["r"], currentState: "둘째 줄" });
});

test("Worklog reads folders, sorts months newest first, rejects traversal", async () => {
  const root = await mkdtemp(join(tmpdir(), "wl-"));
  await mkdir(join(root, "log"));
  await mkdir(join(root, "projects"));
  await writeFile(join(root, "log", "2026-09.md"), "- 09-01 #done a\n");
  await writeFile(join(root, "log", "2026-10.md"), "- 10-01 #done b\n");
  await writeFile(join(root, "log", "notes.md"), "ignored");
  await writeFile(join(root, "projects", "_template.md"), "# tmpl");
  await writeFile(join(root, "projects", "p1.md"), "# P1\n");

  const wl = new Worklog(root);
  assert.deepEqual(await wl.months("log"), ["2026-10", "2026-09"]);
  assert.deepEqual(await wl.months("summaries"), []);
  assert.equal((await wl.log("2026-10"))?.[0].text, "b");
  assert.equal(await wl.log("../etc"), null);
  assert.deepEqual((await wl.projects()).map((p) => p.slug), ["p1"]);
  assert.equal(await wl.project("../log/2026-10"), null);
  assert.equal((await wl.project("p1"))?.title, "P1");
});
