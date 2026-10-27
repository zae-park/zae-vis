import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Api, CliError, formatAnswer, formatHits, formatIndex, formatLog, formatProjects, run } from "../src/cli.ts";
import { createApp } from "../src/app.ts";
import { Worklog } from "../src/worklog.ts";

// stdout is not a TTY under the test runner, so output has no colour codes.

test("formatHits: results, empty, index-not-ready", () => {
  const out = formatHits({ ok: true, query: "q", hits: [{ number: 1, title: "회의", path: "processed/a.txt", snippet: "GA4\n매핑" }] });
  assert.equal(out, "[1] 회의  processed/a.txt\n    GA4 매핑");
  assert.match(formatHits({ ok: true, query: "x", hits: [] }), /결과가 없습니다/);
  assert.match(formatHits({ ok: false, error: { code: "index-not-ready" } }), /zaevis index --refresh/);
});

test("formatAnswer: answer, numbered sources, agent and time", () => {
  const out = formatAnswer({ answer: "10월 26일에 했다 [1].", sources: [{ n: 1, path: "sources/git/2026-10-26.md", label: "2026-10-26 · git 커밋", passage: "…" }], agent: "claude", ms: 12_345 });
  assert.equal(out, "10월 26일에 했다 [1].\n\n근거\n[1] 2026-10-26 · git 커밋  sources/git/2026-10-26.md\n— claude, 12.3초");
});

test("formatLog shows tags in Korean and the source of Claude lines", () => {
  const out = formatLog("2026-10", [
    { date: "10-06", tags: ["done"], projects: ["poc"], text: "연결", source: null },
    { date: "10-08", tags: ["blocked"], projects: [], text: "누락", source: "git r abc" },
  ]);
  assert.equal(out, "2026-10\n10-06  완료 poc  연결\n10-08  막힘  누락  ← git r abc");
});

test("formatProjects and formatIndex", () => {
  assert.equal(formatProjects([{ slug: "p", title: "P", status: "보류", currentState: "a\nb" }]), "p  P [보류]\n    a b");
  const idx = formatIndex({ refreshing: false, autorag: { state: "idle", stale: true, diagnostics: [1, 2, 3, 4, 5].map((i) => ({ message: `m${i}` })) } });
  assert.equal(idx, "상태: idle\n최신: 갱신 필요\n· m1\n· m2\n· m3\n· 외 2건");
});

let server: Server;
let api: Api;

before(async () => {
  const root = await mkdtemp(join(tmpdir(), "zv-cli-"));
  await mkdir(join(root, "log"));
  await mkdir(join(root, "summaries"));
  await writeFile(join(root, "log", "2026-09.md"), "- 09-30 #done 이전 달\n");
  await writeFile(join(root, "log", "2026-10.md"), "- 10-06 #done 이번 달\n");
  await writeFile(join(root, "summaries", "2026-09.md"), "# 2026-09 작업 정리\n");
  const fake = {
    status: async () => ({ state: "fresh" }),
    refresh: async () => ({}),
    search: async (query: string) => ({ ok: true, query, hits: [] }),
    close: async () => {},
  };
  server = createApp({ worklog: new Worklog(root), search: fake });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  api = new Api(`http://127.0.0.1:${(server.address() as AddressInfo).port}`);
});

after(() => server.close());

test("run: log defaults to the newest month, summary to the newest summary", async () => {
  assert.match(await run(api, "log", []), /^2026-10\n.*이번 달/);
  assert.match(await run(api, "log", ["2026-09"]), /이전 달/);
  assert.equal(await run(api, "summary", []), "# 2026-09 작업 정리\n");
});

test("run: errors are CliError with a usable message", async () => {
  await assert.rejects(run(api, "search", []), CliError);
  await assert.rejects(run(api, "log", ["2030-01"]), /찾을 수 없습니다/);
  await assert.rejects(run(api, "nope", []), /알 수 없는 명령/);
  assert.match(await run(api, "index", ["--refresh"]), /색인 갱신을 시작/);
});
