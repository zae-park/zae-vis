import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import { createApp } from "../src/app.ts";
import { normalizeSearch, type SearchBackend } from "../src/autorag.ts";
import { Worklog } from "../src/worklog.ts";

process.env.ZAEVIS_HOME = await mkdtemp(join(tmpdir(), "zv-ds-"));
const { TEMPLATES, findBin, installPlan, knownDatasourceIds, listStatus, probe, readDatasources, readExternalFile, removeDatasource, saveDatasource, shapeConnector, syncRecords, templateByName } = await import("../src/datasources.ts");

const cfgFile = join(process.env.ZAEVIS_HOME, "autorag", "config.json");
await mkdir(join(process.env.ZAEVIS_HOME, "autorag"), { recursive: true });
await writeFile(cfgFile, JSON.stringify({ searchPaths: ["/w"], workspacePath: "/w", rerank: false, datasources: { slack: { enabled: true, connector: { workspace: "T0" } }, nope: { type: "unknown-thing" } } }, null, 2));

test("templates: every AutoRAG template zaevis offers has a title, fields and an install hint when a CLI is needed", () => {
  const names = TEMPLATES.map((t) => t.name);
  for (const n of ["slack", "notion", "discord", "kakao", "whatsapp", "telegram", "mailcrawl", "mail-export", "obsidian", "github", "github-gist", "cloud-drive", "rss", "spotlight"]) assert.ok(names.includes(n), n);
  for (const t of TEMPLATES) {
    assert.ok(t.title && t.description, t.name);
    if (t.cli) assert.ok(t.cli.install, `${t.name} install hint`);
    for (const f of t.fields) assert.ok(["text", "path", "list", "env"].includes(f.kind), `${t.name}.${f.key}`);
  }
  assert.equal(templateByName("obsidian")?.fields[0].key, "vaultPath");
  assert.equal(templateByName("slack")?.fields.find((f) => f.required)?.key, "workspace");
  assert.equal(templateByName("zzz"), undefined);
});

test("probe: missing CLI → not installed; no CLI → null; platform gate; env names only", () => {
  const slack = probe(templateByName("slack")!, {}, { PATH: "/nonexistent" });
  assert.equal(slack.installed, false);
  assert.equal(slack.binPath, null);
  assert.equal(slack.archive, false);
  const obsidian = probe(templateByName("obsidian")!);
  assert.equal(obsidian.installed, null);
  assert.equal(obsidian.unavailable, null);
  const gh = probe(templateByName("github")!, {}, { PATH: "" });
  assert.deepEqual(gh.env, [{ name: "GITHUB_TOKEN", set: false, stored: false }], "default token env is reported by name");
  const gh2 = probe(templateByName("github")!, { tokenEnv: "MY_GH" }, { PATH: "", MY_GH: "x" });
  assert.deepEqual(gh2.env, [{ name: "MY_GH", set: true, stored: false }]);
  assert.ok(!JSON.stringify(gh2).includes('"x"'), "the value never appears");

  assert.equal(installPlan("nope").kind, "none");
  // findBin also looks in the usual install folders, so on a Mac with Homebrew npm these resolve
  const slackPlan = installPlan("slacrawl", { PATH: "/nonexistent" });
  assert.ok(slackPlan.kind === "brew" ? slackPlan.pkg === "openclaw/tap/slacrawl" : /Homebrew/.test(slackPlan.reason));
  const katok = installPlan("lazykatok", { PATH: "/nonexistent" });
  assert.ok(katok.kind === "release" ? katok.repo === "changeroa/lazykatok" && katok.asset("0.3.3")!.includes("0.3.3") && katok.dir.endsWith("ext/bin") : katok.kind === "none");
  assert.equal(installPlan("mailcrawl").kind, "none", "no automated path for mailcrawl yet");
  const rclone = installPlan("rclone", { PATH: "/nonexistent" });
  assert.ok(rclone.kind === "brew" ? rclone.pkg === "rclone" : /Homebrew/.test(rclone.reason));
  const spot = probe(templateByName("spotlight")!);
  assert.equal(spot.unavailable === null, process.platform === "darwin");
  assert.equal(findBin("node") !== null, true, "node is on PATH");
  assert.equal(findBin("definitely-not-a-binary-zaevis"), null);
});

test("shapeConnector: typed fields, required check, env names, no secrets", () => {
  const rss = shapeConnector(templateByName("rss")!, { feeds: "https://a.com/f\n\nhttps://b.com/f" });
  assert.deepEqual(rss, { feeds: [{ url: "https://a.com/f" }, { url: "https://b.com/f" }] });
  assert.throws(() => shapeConnector(templateByName("rss")!, { feeds: ["ftp://x"] }), /http\(s\)/);
  assert.throws(() => shapeConnector(templateByName("rss")!, {}), /피드 주소/);
  const gh = shapeConnector(templateByName("github")!, { repos: ["a/b", " c/d "], tokenEnv: "GH_TOKEN", maxPages: 3 });
  assert.deepEqual(gh, { repos: ["a/b", "c/d"], tokenEnv: "GH_TOKEN", maxPages: 3 });
  assert.throws(() => shapeConnector(templateByName("github")!, { repos: ["a/b"], tokenEnv: "ghp_abc" }), /환경 변수 이름/);
  assert.throws(() => shapeConnector(templateByName("github")!, { repos: ["a/b"], token: "ghp_abc" }), /저장할 수 없습니다/);
  assert.throws(() => shapeConnector(templateByName("github")!, { repos: ["not a repo"] }), /owner\/repo/);
  const ob = shapeConnector(templateByName("obsidian")!, { vaultPath: "~/Vault" });
  assert.ok((ob.vaultPath as string).startsWith("/") && (ob.vaultPath as string).endsWith("/Vault"), "~ expanded");
  assert.throws(() => shapeConnector(templateByName("obsidian")!, { vaultPath: "" }), /볼트 폴더/);
});

test("config: read, save (other keys kept), alias, disable, remove", async () => {
  const before = readDatasources(cfgFile);
  assert.deepEqual(Object.keys(before), ["slack", "nope"]);
  const saved = saveDatasource(cfgFile, "obsidian", { connector: { vaultPath: "/tmp/vault" }, description: "내 노트" });
  assert.deepEqual(saved, { enabled: true, description: "내 노트", connector: { vaultPath: "/tmp/vault" } });
  const file = JSON.parse(await readFile(cfgFile, "utf8"));
  assert.deepEqual(file.searchPaths, ["/w"], "other keys untouched");
  assert.equal(file.rerank, false);
  assert.deepEqual(file.datasources.slack, { enabled: true, connector: { workspace: "T0" } }, "other connections untouched");
  assert.deepEqual(file.datasources.obsidian, saved);
  // patch without connector keeps it; enabled false disables
  saveDatasource(cfgFile, "obsidian", { enabled: false });
  assert.deepEqual(readDatasources(cfgFile).obsidian, { enabled: false, description: "내 노트", connector: { vaultPath: "/tmp/vault" } });
  // alias with type
  saveDatasource(cfgFile, "team-feeds", { type: "rss", connector: { feeds: ["https://x.com/rss"] } });
  assert.deepEqual(readDatasources(cfgFile)["team-feeds"], { type: "rss", enabled: true, connector: { feeds: [{ url: "https://x.com/rss" }] } });
  assert.throws(() => saveDatasource(cfgFile, "team-feeds", { type: "team-feeds" }), /별칭/);
  assert.throws(() => saveDatasource(cfgFile, "Bad Name", {}), /이름은/);
  assert.throws(() => saveDatasource(cfgFile, "what", {}), /모르는 데이터소스/);
  assert.throws(() => saveDatasource(cfgFile, "github", { connector: { repos: ["a/b"], token: "secret" } }), /저장할 수 없습니다/);
  assert.ok(knownDatasourceIds(cfgFile).includes("team-feeds") && knownDatasourceIds(cfgFile).includes("obsidian"));
  // status rows: templates first, then the alias; unknown-type entries are left out
  const rows = listStatus(cfgFile, [{ datasourceId: "slack", name: "slack", type: "chat", status: "active", sourceScopes: ["/slack/default"] }], { slack: { lastSync: "2026-10-27T00:00:00Z", ok: true, chunks: 12 } }, { PATH: "" });
  const slack = rows.find((r) => r.name === "slack")!;
  assert.equal(slack.configured, true);
  assert.equal(slack.enabled, true);
  assert.equal(slack.probe.installed, false);
  assert.equal(slack.autorag?.status, "active");
  assert.equal(slack.sync?.chunks, 12);
  const ob = rows.find((r) => r.name === "obsidian")!;
  assert.equal(ob.enabled, false);
  assert.equal(ob.note, "내 노트");
  assert.equal(rows.find((r) => r.name === "notion")!.configured, false);
  const alias = rows.find((r) => r.name === "team-feeds")!;
  assert.equal(alias.template, "rss");
  assert.equal(alias.title, "RSS · 뉴스 (team-feeds)");
  assert.deepEqual(alias.connector, { feeds: ["https://x.com/rss"] }, "feeds shown as plain URLs");
  assert.equal(rows.some((r) => r.name === "nope"), false);
  assert.equal(rows.findIndex((r) => r.name === "team-feeds") > rows.findIndex((r) => r.name === "hister"), true);
  // remove
  assert.equal(removeDatasource(cfgFile, "team-feeds"), true);
  assert.equal(removeDatasource(cfgFile, "team-feeds"), false);
  assert.deepEqual(Object.keys(readDatasources(cfgFile)), ["slack", "nope", "obsidian"]);
});

test("syncRecords: per-connection outcome, or everything failed", () => {
  const ok = syncRecords({ datasources: [{ ok: true, skill: "obsidian", instanceId: "default", chunkCount: 2, indexedAt: 1793080082635 }, { ok: false, skill: "slack", instanceId: "default", error: "binary-missing", indexedAt: 1793080082635 }] }, undefined, ["obsidian", "slack"]);
  assert.deepEqual(ok, { obsidian: { lastSync: "2026-10-27T05:48:02.635Z", ok: true, chunks: 2 }, slack: { lastSync: "2026-10-27T05:48:02.635Z", ok: false, error: "binary-missing" } });
  const failed = syncRecords(null, "boom", ["obsidian"]);
  assert.equal(failed.obsidian.ok, false);
  assert.equal(failed.obsidian.error, "boom");
  assert.deepEqual(syncRecords({ scanned: 0 }, undefined, ["obsidian"]), {}, "a refresh without the phase records nothing");
});

test("readExternalFile: obsidian notes come from the vault, nothing else does", async () => {
  const vault = await mkdtemp(join(tmpdir(), "zv-vault-"));
  await mkdir(join(vault, "프로젝트"));
  await writeFile(join(vault, "프로젝트", "연결.md"), "# 연결\n본문");
  saveDatasource(cfgFile, "obsidian", { enabled: true, connector: { vaultPath: vault } });
  assert.deepEqual(readExternalFile(cfgFile, "/obsidian/default/프로젝트/연결.md"), { path: "/obsidian/default/프로젝트/연결.md", markdown: "# 연결\n본문" });
  assert.equal(readExternalFile(cfgFile, "/obsidian/default/../../etc/passwd"), null);
  assert.equal(readExternalFile(cfgFile, "/obsidian/default/없음.md"), null);
  assert.equal(readExternalFile(cfgFile, "/slack/default/C1/x.md"), null);
  assert.equal(readExternalFile(cfgFile, "log/2026-10.md"), null);
});

test("normalizeSearch: an external hit keeps its source and gets the datasource context", () => {
  const r = normalizeSearch("청록앵무", {
    ok: true,
    results: [
      { number: 1, source: "/private/tmp/w/worklog/log/2026-10.md", score: 1, metadata: { method: "minsync" }, content: "- 10-20 청록앵무 시작" },
      { number: 2, source: "/obsidian/default/회의.md", score: 0.9, metadata: { method: "obsidian-bm25", datasourceId: "obsidian", instanceId: "default", title: "회의", path: "/v/회의.md" }, content: "# 회의 메모\n\n청록앵무 킥오프." },
    ],
  }, ["/tmp/w/worklog"]);
  assert.equal(r.hits[0].path, "log/2026-10.md");
  assert.equal(r.hits[0].context.kind, "log");
  assert.equal(r.hits[1].path, "/obsidian/default/회의.md");
  assert.equal(r.hits[1].title, "회의");
  assert.equal(r.hits[1].context.kind, "external");
  assert.equal(r.hits[1].context.sourceLabel, "Obsidian 볼트");
  assert.equal(r.hits[1].context.datasource, "obsidian");
  assert.equal(r.hits[1].context.file, "/v/회의.md");
});

// ── HTTP routes ─────────────────────────────────────────────────────────────────

let server: Server;
let base: string;
const refreshes: Array<{ force: boolean; phases?: string[] }> = [];
let restarts = 0;
const saved: Array<[string, Record<string, unknown>]> = [];
const synced: unknown[] = [];

const fake: SearchBackend = {
  async status() {
    return { state: "fresh" };
  },
  async refresh(force = false, phases) {
    refreshes.push({ force, phases });
    return { ok: true, datasources: [{ ok: true, skill: "obsidian", instanceId: "default", chunkCount: 1, indexedAt: 0 }] };
  },
  async search(query) {
    return { ok: true, query, hits: [] };
  },
  async datasources() {
    return [{ datasourceId: "obsidian", status: "active" }];
  },
  async restart() {
    restarts++;
  },
  async close() {},
};

before(async () => {
  const root = await mkdtemp(join(tmpdir(), "zv-ds-wl-"));
  await mkdir(join(root, "log"));
  server = createApp({
    worklog: new Worklog(root),
    search: fake,
    datasources: {
      list: async () => listStatus(cfgFile, (await fake.datasources!()) as never, {}, { PATH: "" }),
      async save(name, patch) {
        saved.push([name, patch]);
        const e = saveDatasource(cfgFile, name, patch as never);
        return { enabled: e.enabled !== false };
      },
      remove: async (name) => removeDatasource(cfgFile, name),
      file: async (p) => readExternalFile(cfgFile, p),
      recordSync: (r, e) => synced.push([r, e]),
    },
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(() => server.close());

const call = async (method: string, p: string, body?: unknown) => {
  const r = await fetch(base + p, { method, headers: { "content-type": "application/json", "x-zaevis": "1" }, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: r.status, body: (await r.json()) as Record<string, any> };
};
const settle = () => new Promise((r) => setTimeout(r, 20));

test("GET /api/datasources lists templates with probe, config and AutoRAG state", async () => {
  const r = await call("GET", "/api/datasources");
  assert.equal(r.status, 200);
  assert.equal(r.body.syncing, false);
  const rows = r.body.datasources as Array<Record<string, any>>;
  assert.ok(rows.length >= 14);
  const slack = rows.find((x) => x.name === "slack");
  assert.equal(slack.configured, true);
  assert.equal(slack.probe.installed, false);
  assert.equal(slack.cli.install, "brew install openclaw/tap/slacrawl");
  assert.equal(rows.find((x) => x.name === "obsidian").autorag.status, "active");
});

test("PUT /api/datasources/:name saves, restarts the child and syncs the datasources phase", async () => {
  const r = await call("PUT", "/api/datasources/rss", { connector: { feeds: ["https://x.com/rss"] }, description: "뉴스" });
  assert.equal(r.status, 200);
  assert.equal(r.body.syncing, true);
  await settle();
  assert.deepEqual(refreshes.at(-1), { force: false, phases: ["datasources"] });
  assert.equal(saved.at(-1)![0], "rss");
  assert.equal(readDatasources(cfgFile).rss.description, "뉴스");
  assert.equal(synced.length, 1, "the sync outcome is recorded");
  const bad = await call("PUT", "/api/datasources/github", { connector: { repos: ["a/b"], token: "ghp_x" } });
  assert.equal(bad.status, 400);
  assert.match(bad.body.message, /저장할 수 없습니다/);
  assert.equal("github" in readDatasources(cfgFile), false);
  // disabling does not start a sync
  const n = refreshes.length;
  assert.equal((await call("PUT", "/api/datasources/rss", { enabled: false })).status, 200);
  await settle();
  assert.equal(refreshes.length, n);
  assert.equal(readDatasources(cfgFile).rss.enabled, false);
});

test("POST /api/datasources/:name/sync and DELETE", async () => {
  const s = await call("POST", "/api/datasources/obsidian/sync");
  assert.equal(s.status, 202);
  await settle();
  assert.deepEqual(refreshes.at(-1), { force: false, phases: ["datasources"] });
  assert.equal((await call("POST", "/api/datasources/obsidian/nope")).status, 404);
  assert.equal((await call("DELETE", "/api/datasources/rss")).status, 200);
  assert.equal((await call("DELETE", "/api/datasources/rss")).status, 404);
  assert.equal("rss" in readDatasources(cfgFile), false);
  assert.equal((await call("GET", "/api/datasources/rss")).status, 404);
});

test("GET /api/file serves an Obsidian note behind an external hit", async () => {
  const vault = String(readDatasources(cfgFile).obsidian.connector!.vaultPath);
  const r = await call("GET", "/api/file?path=" + encodeURIComponent("/obsidian/default/프로젝트/연결.md"));
  assert.equal(r.status, 200);
  assert.equal(r.body.markdown, "# 연결\n본문");
  assert.ok(vault);
  assert.equal((await call("GET", "/api/file?path=" + encodeURIComponent("/slack/default/x.md"))).status, 404);
});
