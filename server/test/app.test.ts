import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { createApp } from "../src/app.ts";
import { normalizeSearch, type SearchBackend } from "../src/autorag.ts";
import { Worklog } from "../src/worklog.ts";

let server: Server;
let base: string;
const calls: string[] = [];

const fake: SearchBackend = {
  async status() {
    calls.push("status");
    return { state: "fresh" };
  },
  async refresh() {
    calls.push("refresh");
    return { ok: true };
  },
  async search(query, topK) {
    calls.push(`search:${query}:${topK}`);
    return { ok: true, query, hits: [{ number: 1, title: "t", path: "log/2026-10.md", snippet: "s", score: 1 }] };
  },
  async close() {},
};

before(async () => {
  const root = await mkdtemp(join(tmpdir(), "wl-app-"));
  await mkdir(join(root, "log"));
  await mkdir(join(root, "summaries"));
  await mkdir(join(root, "projects"));
  await writeFile(join(root, "log", "2026-10.md"), "- 10-06 [[p]] #done 완료 (src: git r abc1234)\n");
  await writeFile(join(root, "summaries", "2026-09.md"), "# 2026-09 작업 정리\n");
  await writeFile(join(root, "projects", "p.md"), "---\nstatus: 진행 중\n---\n# P\n");
  const web = await mkdtemp(join(tmpdir(), "wl-web-"));
  await writeFile(join(web, "index.html"), "<html>app</html>");
  server = createApp({ worklog: new Worklog(root), search: fake, webDir: web });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

after(() => server.close());

const get = async (p: string, init?: RequestInit) => {
  const r = await fetch(base + p, init);
  return { status: r.status, body: r.headers.get("content-type")?.includes("json") ? await r.json() : await r.text(), headers: r.headers };
};

test("logs list and month", async () => {
  assert.deepEqual((await get("/api/logs")).body, { months: ["2026-10"] });
  const m = await get("/api/logs/2026-10");
  assert.equal(m.body.entries[0].author, "claude");
  assert.equal((await get("/api/logs/2026-11")).status, 404);
  assert.equal((await get("/api/logs/..%2F..%2Fetc")).status, 404);
});

test("summaries and projects", async () => {
  assert.deepEqual((await get("/api/summaries")).body, { months: ["2026-09"] });
  assert.match((await get("/api/summaries/2026-09")).body.markdown, /작업 정리/);
  assert.equal((await get("/api/projects")).body.projects[0].status, "진행 중");
  assert.equal((await get("/api/projects/p")).body.title, "P");
});

test("search validates and clamps topK", async () => {
  assert.equal((await get("/api/search")).status, 400);
  const r = await get("/api/search?q=" + encodeURIComponent("GA4 매핑") + "&topK=999");
  assert.equal(r.body.hits.length, 1);
  assert.ok(calls.includes("search:GA4 매핑:50"));
});

test("index refresh runs once in the background", async () => {
  const r = await get("/api/index", { method: "POST", body: "{}" });
  assert.equal(r.status, 202);
  await new Promise((res) => setTimeout(res, 20));
  const s = await get("/api/index");
  assert.equal(s.body.lastRefresh.ok, true);
  assert.equal(s.body.autorag.state, "fresh");
});

test("CORS only for localhost origins", async () => {
  const ok = await get("/api/health", { headers: { origin: "http://localhost:53211" } });
  assert.equal(ok.headers.get("access-control-allow-origin"), "http://localhost:53211");
  const bad = await get("/api/health", { headers: { origin: "https://evil.example" } });
  assert.equal(bad.headers.get("access-control-allow-origin"), null);
});

test("serves web app with SPA fallback, unknown api is 404", async () => {
  assert.equal((await get("/")).body, "<html>app</html>");
  assert.equal((await get("/search/deep/link")).body, "<html>app</html>");
  assert.equal((await get("/api/nope")).status, 404);
});

test("normalizeSearch maps errors and common result fields", () => {
  const err = normalizeSearch("q", { ok: false, errorCode: "index-not-ready", message: "refresh first" });
  assert.deepEqual(err.error, { code: "index-not-ready", message: "refresh first" });
  const okr = normalizeSearch("q", { results: [{ title: "T", path: "/worklog/log/2026-10.md", summary: " s ", score: 0.5 }] }, ["/x"]);
  assert.deepEqual(okr.hits[0], { number: 1, title: "T", path: "log/2026-10.md", snippet: "s", score: 0.5 });
});

test("normalizeSearch handles the AutoRAG 2.11 Lite shape (source string + content)", () => {
  const lite = {
    ok: true,
    query: "GA4",
    stale: false,
    results: [
      { number: 1, source: "/worklog/processed/transcripts/2026-10-09_회의.txt", method: "bm25", score: 3.2, metadata: {}, content: "GA4 캠페인 매핑이 빠져서 ".repeat(60) },
    ],
  };
  const r = normalizeSearch("GA4", lite, ["/Users/me/worklog"]);
  assert.equal(r.hits[0].path, "processed/transcripts/2026-10-09_회의.txt");
  assert.equal(r.hits[0].title, "2026-10-09_회의.txt");
  assert.equal(r.hits[0].score, 3.2);
  assert.ok(r.hits[0].snippet.length <= 601 && r.hits[0].snippet.endsWith("…"));
});

test("AutoRAGMcp without a config explains how to set it up instead of crashing", async () => {
  const { AutoRAGMcp } = await import("../src/autorag.ts");
  const m = new AutoRAGMcp({ configPath: "/nonexistent/config.json", roots: [] });
  const r = await m.search("q", 5);
  assert.equal(r.ok, false);
  assert.equal(r.error?.code, "not-configured");
  assert.equal(((await m.status()) as { state: string }).state, "not-configured");
  await assert.rejects(m.refresh(), /zaevis setup/);
});
