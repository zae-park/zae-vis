import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { candidateFiles, candidateLines, contentDisposition, listWorklogFiles, type CatalogFile } from "../src/files.ts";

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
test("candidates: what the chat showed first, then the newest few of each folder; name lists left out", () => {
  const c = candidateFiles(catalog, { pinned: [{ path: "projects/rosetta.md", note: "앞 화면 [2]" }, { path: "없음.md" }], perFolder: 2 });
  assert.deepEqual(c[0], { path: "projects/rosetta.md", name: "rosetta.md", bytes: 10, date: null, kind: "프로젝트", note: "앞 화면 [2]" });
  const paths = c.map((x) => x.path);
  assert.ok(paths.indexOf("inbox/transcripts/2026-11-02_1703_녹음.txt") < paths.indexOf("inbox/transcripts/2026-10-30_1424_녹음.txt"), "newest first");
  assert.ok(!paths.includes("inbox/transcripts/2026-10-26_2115_녹음.txt"), "two per folder");
  assert.ok(!paths.includes("sources/transcripts/2026-11-02.md"), "the collector's list of names is not a file anyone asks for");
  assert.equal(c.find((x) => x.path === "sources/calendar/2026-11-02.md")?.kind, "calendar");
  assert.match(candidateLines(c.slice(0, 1)), /^- projects\/rosetta\.md · 프로젝트 · 1KB \(앞 화면 \[2\]\)$/);
  assert.equal(candidateFiles(catalog, { max: 3 }).length, 3);
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

