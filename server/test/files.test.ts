import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { contentDisposition, filesNamedIn, findFiles, listWorklogFiles, parseRequest, type CatalogFile } from "../src/files.ts";

const now = new Date(2026, 10, 2, 18, 0); // 2026-11-02
const f = (path: string, mtime = 0): CatalogFile => ({ path, name: path.split("/").pop()!, bytes: 10, mtime });
const catalog = [
  f("inbox/transcripts/2026-10-26_2115_녹음.txt"),
  f("inbox/transcripts/2026-10-30_1424_녹음.txt"),
  f("inbox/transcripts/2026-11-02_1703_녹음.txt"),
  f("sources/transcripts/2026-11-02.md"),
  f("sources/git/2026-11-02.md"),
  f("sources/git/2026-11-01.md"),
  f("sources/shell-history/2026-11-01.md"),
  f("sources/calendar/2026-11-02.md"),
  f("reports/daily/2026-11-01.md"),
  f("reports/weekly/2026-W44.md"),
  f("summaries/2026-10.md"),
  f("log/2026-10.md"),
  f("projects/zaevis.md"),
  f("projects/rosetta.md"),
  f("README.md"),
];
const paths = (q: string) => findFiles(catalog, q, now).map((x) => x.path);

test("a date and a kind pick that day's transcripts", () => {
  assert.deepEqual(paths("11월 2일 전사본 txt로 다운받아줘"), ["inbox/transcripts/2026-11-02_1703_녹음.txt"], "not the collector's list of names");
  assert.deepEqual(paths("2026-10-30 녹음 내려받기"), ["inbox/transcripts/2026-10-30_1424_녹음.txt"]);
  assert.deepEqual(paths("10/26 회의록"), ["inbox/transcripts/2026-10-26_2115_녹음.txt"]);
});

test("a time narrows to one recording; 가장 최근 keeps only the newest", () => {
  assert.deepEqual(paths("14:24 녹음 파일"), ["inbox/transcripts/2026-10-30_1424_녹음.txt"]);
  assert.deepEqual(paths("오후 9시 15분 녹음"), [], "오후 9시 is 21시; the hour is taken as written");
  assert.deepEqual(paths("21시 15분 녹음"), ["inbox/transcripts/2026-10-26_2115_녹음.txt"]);
  assert.deepEqual(paths("가장 최근 전사본 다운로드"), ["inbox/transcripts/2026-11-02_1703_녹음.txt"]);
});

test("오늘·어제, other kinds, connector folders and project names", () => {
  assert.deepEqual(paths("어제 셸 이력"), ["sources/shell-history/2026-11-01.md"]);
  assert.deepEqual(paths("오늘 git 커밋 파일"), ["sources/git/2026-11-02.md"]);
  assert.deepEqual(paths("calendar 11월 2일"), ["sources/calendar/2026-11-02.md"]);
  assert.deepEqual(paths("일간 리포트 11/1"), ["reports/daily/2026-11-01.md"]);
  assert.deepEqual(paths("10월 월간 정리"), ["summaries/2026-10.md"]);
  assert.deepEqual(paths("rosetta 프로젝트 파일 줘"), ["projects/rosetta.md"]);
  assert.deepEqual(paths("rosetta를 받고 싶어"), ["projects/rosetta.md"]);
});

test("an exact path or file name wins; a request that names nothing finds nothing", () => {
  assert.deepEqual(paths("inbox/transcripts/2026-10-30_1424_녹음.txt 다운로드"), ["inbox/transcripts/2026-10-30_1424_녹음.txt"]);
  assert.deepEqual(paths("README.md 줘"), ["README.md"]);
  assert.deepEqual(paths("다운로드 해줘"), []);
  assert.deepEqual(paths("색인 미룬 이유 파일"), []);
});

test("parseRequest: a month later than now is last year; filler words are not search words", () => {
  const w = parseRequest("12월 3일 회의 전사본을 텍스트 파일로 내려받고 싶어", now);
  assert.deepEqual(w.days, ["2025-12-03"]);
  assert.deepEqual(w.kinds.map((k) => k.label), ["전사본"]);
  assert.ok(!w.tokens.some((x) => /회의|텍스트|파일|내려받|싶/.test(x)), w.tokens.join(","));
});

test("listWorklogFiles walks .md/.txt and skips dot folders and audio", async () => {
  const root = await mkdtemp(join(tmpdir(), "wl-files-"));
  await mkdir(join(root, "inbox", "audio"), { recursive: true });
  await mkdir(join(root, "inbox", "transcripts"), { recursive: true });
  await mkdir(join(root, ".git"));
  await writeFile(join(root, "inbox", "audio", "a.txt"), "x");
  await writeFile(join(root, "inbox", "transcripts", "t.txt"), "x");
  await writeFile(join(root, ".git", "HEAD.md"), "x");
  await writeFile(join(root, "a.wav"), "x");
  assert.deepEqual((await listWorklogFiles(root)).map((x) => x.path), ["inbox/transcripts/t.txt"]);
});

test("contentDisposition keeps a Korean name for browsers and an ASCII fallback", () => {
  assert.equal(contentDisposition("2026-11-02_1703_녹음.txt"), `attachment; filename="2026-11-02_1703___.txt"; filename*=UTF-8''2026-11-02_1703_%EB%85%B9%EC%9D%8C.txt`);
});

test("a question names files by kind plus date or latest; content questions name none", () => {
  const named = (q: string) => filesNamedIn(catalog, q, now).map((x) => x.path);
  assert.deepEqual(named("가장 최근에 진행한 회의의 회의록을 받고싶어"), ["inbox/transcripts/2026-11-02_1703_녹음.txt"]);
  assert.deepEqual(named("가장 최근 회의 내용 요약해줘"), ["inbox/transcripts/2026-11-02_1703_녹음.txt"]);
  assert.deepEqual(named("10월 30일 회의에서 정한 것"), ["inbox/transcripts/2026-10-30_1424_녹음.txt"]);
  assert.deepEqual(named("회의에서 정한 배포 일정"), [], "no date: search finds it by content");
  assert.deepEqual(named("가장 최근에 한 일"), [], "no kind of record");
});
