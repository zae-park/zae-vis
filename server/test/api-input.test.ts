import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { request } from "node:http";
import { createApp } from "../src/app.ts";
import { Worklog } from "../src/worklog.ts";

let server: Server;
let base: string;
let root: string;
const calls: string[] = [];
let added: Array<Record<string, unknown>> = [];
const queued: string[] = [];
let indexOnInject = false;

before(async () => {
  root = await mkdtemp(join(tmpdir(), "zv-in-"));
  await mkdir(join(root, "log"));
  server = createApp({
    worklog: new Worklog(root),
    search: {
      status: async () => ({ state: "fresh" }),
      refresh: async () => {
        calls.push("refresh");
      },
      search: async (q) => ({ ok: true, query: q, hits: [] }),
      close: async () => {},
    },
    sources: {
      list: () => [{ name: "git", enabled: true }, ...added],
      collect: async (only) => {
        calls.push(`collect:${only?.join(",") ?? "all"}`);
        return [{ name: "git", ok: true, days: ["2026-10-23"] }];
      },
      update: (name, patch) => calls.push(`update:${name}:${JSON.stringify(patch)}`),
      add: (s) => {
        added.push(s);
      },
      remove: (name) => {
        const n = added.length;
        added = added.filter((x) => x.name !== name);
        return added.length < n;
      },
    },
    settings: {
      get: async () => ({ dailyAt: "18:30", indexOnInject }),
      update: async (p) => {
        if (p.dailyAt && !/^\d{2}:\d{2}$/.test(p.dailyAt)) throw new Error("시각 형식");
        if (p.indexOnInject !== undefined) indexOnInject = p.indexOnInject;
        return { dailyAt: p.dailyAt ?? "18:30", indexOnInject };
      },
      indexOnInject: () => indexOnInject,
    },
    audio: { dir: () => join(root, "inbox", "audio"), enqueue: (f) => queued.push(f), jobs: () => [] },
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

after(() => server.close());

const H = { "content-type": "application/json", "x-zaevis": "1" };
const call = async (method: string, p: string, body?: unknown, headers: Record<string, string> = H) => {
  const r = await fetch(base + p, { method, headers, body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body) });
  return { status: r.status, body: await r.json().catch(() => null) };
};
const tick = () => new Promise((r) => setTimeout(r, 30));

test("mutations need the x-zaevis header and a local origin; rebound hosts are refused", async () => {
  assert.equal((await call("POST", "/api/sources", { name: "x", command: "id" }, { "content-type": "text/plain" })).status, 403);
  assert.equal((await call("POST", "/api/sources", { name: "x", command: "id" }, { ...H, origin: "https://evil.example" })).status, 403);
  const rebound = await new Promise<number>((resolve) => {
    const u = new URL(base);
    request({ host: u.hostname, port: u.port, path: "/api/health", headers: { host: "evil.example:4710" } }, (res) => resolve(res.statusCode ?? 0)).end();
  });
  assert.equal(rebound, 403);
  assert.equal(added.length, 0);
});

test("POST /api/logs appends a formatted line and validates input", async () => {
  const r = await call("POST", "/api/logs", { text: "GA4 매핑\n수동으로 채움", tags: ["decision"], projects: ["roas"], date: "2026-10-23" });
  assert.equal(r.status, 201);
  assert.equal(r.body.line, "- 10-23 [[roas]] #decision GA4 매핑 수동으로 채움");
  assert.match(await readFile(join(root, "log", "2026-10.md"), "utf8"), /^# 2026-10 로그\n\n- 10-23 \[\[roas\]\] #decision GA4 매핑 수동으로 채움\n$/);
  assert.equal((await call("POST", "/api/logs", { text: "  " })).status, 400);
  assert.equal((await call("POST", "/api/logs", { text: "x", projects: ["../etc"] })).status, 400);
  assert.ok(!calls.includes("refresh"), "no re-index unless indexOnInject");
});

test("transcript paste and audio upload land in the inbox; audio is queued", async () => {
  const t = await call("POST", "/api/inbox/transcripts", { name: "주간 회의.txt", text: "회의 내용" });
  assert.equal(t.status, 201);
  assert.match(t.body.file, /^\d{4}-\d{2}-\d{2}_주간_회의\.txt$/);

  const bad = await call("POST", "/api/inbox/audio?name=evil.sh", "x", { "x-zaevis": "1", "content-type": "application/octet-stream" });
  assert.equal(bad.status, 400);
  const up = await fetch(base + "/api/inbox/audio?name=" + encodeURIComponent("녹음 1.m4a"), { method: "POST", headers: { "x-zaevis": "1", "content-type": "application/octet-stream" }, body: Buffer.alloc(300_000, 1) });
  assert.equal(up.status, 202);
  assert.equal(queued.length, 1);
  const files = await readdir(join(root, "inbox", "audio"));
  assert.equal(files.length, 1);
  assert.match(files[0], /_녹음_1\.m4a$/);

  const inbox = await call("GET", "/api/inbox");
  assert.equal(inbox.body.transcripts.length, 1);
  assert.equal(inbox.body.audio[0].size, 300_000);
});

test("indexOnInject re-indexes right after input", async () => {
  await call("PUT", "/api/settings", { indexOnInject: true });
  await call("POST", "/api/logs", { text: "바로 색인" });
  await tick();
  assert.ok(calls.includes("refresh"));
  await call("PUT", "/api/settings", { indexOnInject: false });
  assert.equal((await call("PUT", "/api/settings", { dailyAt: "7pm" })).status, 400);
});

test("sources: add custom, toggle, remove; collect runs in background then indexes", async () => {
  assert.equal((await call("POST", "/api/sources", { name: "Bad!", command: "x" })).status, 400);
  assert.equal((await call("POST", "/api/sources", { name: "slack", command: "python3 export.py" })).status, 201);
  assert.equal((await call("GET", "/api/sources")).body.sources.length, 2);
  await call("PUT", "/api/sources/git", { enabled: false, settings: { depth: 2, name: "hijack" } });
  assert.ok(calls.includes('update:git:{"enabled":false,"depth":2}'));
  assert.equal((await call("DELETE", "/api/sources/slack")).status, 200);
  assert.equal((await call("DELETE", "/api/sources/git")).status, 400);

  calls.length = 0;
  assert.equal((await call("POST", "/api/collect", { sources: ["git"] })).status, 202);
  await tick();
  assert.deepEqual(calls, ["collect:git", "refresh"]);
  const st = await call("GET", "/api/collect");
  assert.equal(st.body.lastCollect.report[0].name, "git");
});
