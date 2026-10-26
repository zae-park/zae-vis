import assert from "node:assert/strict";
import { test } from "node:test";
import { bestPassage, classifyPath, describeHit, gitAuthor, queryTerms, sectionAbove, stemKo } from "../src/context.ts";

test("classifyPath: sources, log, projects, summaries, inbox", () => {
  assert.deepEqual(classifyPath("sources/git/2026-10-26.md"), { kind: "git", sourceLabel: "git 커밋", date: "2026-10-26" });
  assert.deepEqual(classifyPath("sources/claude-code/2026-10-21.md"), { kind: "claude-code", sourceLabel: "Claude Code 세션", date: "2026-10-21" });
  assert.deepEqual(classifyPath("sources/slack/2026-10-21.md"), { kind: "custom", sourceLabel: "slack (커넥터)", date: "2026-10-21" });
  assert.deepEqual(classifyPath("log/2026-10.md"), { kind: "log", sourceLabel: "한 줄 기록", date: "2026-10" });
  assert.deepEqual(classifyPath("projects/roas.md"), { kind: "project", sourceLabel: "프로젝트", date: null });
  assert.deepEqual(classifyPath("summaries/2026-09.md"), { kind: "summary", sourceLabel: "월간 정리", date: "2026-09" });
  assert.equal(classifyPath("inbox/transcripts/2026-10-06_회의.md").sourceLabel, "회의 전사본");
  assert.equal(classifyPath("README.md").kind, "other");
  assert.deepEqual(classifyPath("tmp/zv-home/worklog/sources/git/2026-10-26.md"), { kind: "git", sourceLabel: "git 커밋", date: "2026-10-26" });
  assert.equal(classifyPath("/Users/me/worklog/log/2026-10.md").kind, "log");
});

test("queryTerms: particles stripped, content words kept, bigrams only for long words", () => {
  assert.equal(stemKo("음성에서"), "음성");
  assert.equal(stemKo("자동으로"), "자동");
  assert.equal(stemKo("모으는"), "모으");
  assert.equal(stemKo("서명"), "서명", "nothing stripped when the stem would be shorter than 2");
  assert.equal(stemKo("cmake"), "cmake");
  assert.deepEqual(queryTerms("음성에서 화자를 나누는 작업"), ["음성", "화자", "나누", "작업"]);
  const long = queryTerms("DMG 설치파일 서명");
  assert.ok(long.includes("dmg") && long.includes("설치파일") && long.includes("설치") && long.includes("치파") && long.includes("서명"));
  assert.ok(!long.includes("서"), "single characters are not terms");
});

test("bestPassage: picks the matching line and grows around it; skips headers", () => {
  const content = "# claude-code · 2026-10-21\n\n<!-- auto -->\n\n## 10:12 화자 분리 작업\n\n- 폴더: `~/jaepark/crea`\n- 요청 (3):\n  - 화자별로 음성 성별을 나눌 수 없다고?\n  - 다른 질문\n- 수정한 파일 (1): `speaker_voice_plan.py`\n\n## 다른 세션\n\n- 폴더: x";
  const h = bestPassage(content, "화자 분리", 200);
  assert.match(h.passage, /^## 10:12 화자 분리 작업\n- 폴더/, "a matching heading brings the lines after the blank line");
  const r = bestPassage(content, "화자별 음성 성별", 200);
  assert.equal(r.lineIndex, 8);
  assert.match(r.passage, /^- 폴더|^- 요청|화자별로 음성 성별/);
  assert.ok(r.passage.includes("화자별로 음성 성별을 나눌 수 없다고?"));
  assert.ok(!r.passage.includes("다른 세션"), "window stops at the next heading");
  assert.ok(r.matched.includes("화자별"));
  assert.equal(sectionAbove(content, r.lineIndex), "10:12 화자 분리 작업");
});

test("bestPassage: no term in common → first substantive lines, not the file header", () => {
  const content = "# git · 2026-10-22\n\n<!-- auto -->\n\n## crea\n\n- 03:04 `c6708b7` feat(spoken_line): intro narration — 박재";
  const r = bestPassage(content, "완전히 다른 질의", 200);
  assert.match(r.passage, /^- 03:04/);
  assert.deepEqual(r.matched, []);
});

test("gitAuthor and describeHit", () => {
  assert.equal(gitAuthor("- 11:17 `4d8dc2d` 앱 — 박재"), "박재");
  assert.equal(gitAuthor("- 11:17 `4d8dc2d` 앱 — 설명 — 홍길동"), "홍길동");
  assert.equal(gitAuthor("- 10-06 [[p]] #done 한 줄"), null);
  const h = describeHit("sources/git/2026-10-26.md", "# git\n\n## zaevis\n\n- 11:17 `4d8dc2d` DMG 패키징 — 박재", "DMG");
  assert.equal(h.author, "박재");
  assert.equal(h.section, "zaevis");
  assert.equal(h.date, "2026-10-26");
  const c = describeHit("sources/claude-code/2026-10-26.md", "## 세션\n\n- 요청: DMG 만들기 — 설명", "DMG");
  assert.equal(c.author, null, "only git lines carry an author");
});
