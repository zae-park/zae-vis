import assert from "node:assert/strict";
import { mkdtemp, readFile, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

process.env.ZAEVIS_HOME = await mkdtemp(join(tmpdir(), "zv-rerank-"));
const { applyToAutoragConfig, childEnv, getKey, keyHint, secretsFile, setKey, status, testKey } = await import("../src/rerank.ts");

test("rerank: key is stored with mode 0600 and only hinted back", async () => {
  assert.equal(getKey(), null);
  setKey("sk-or-v1-abcdef1234");
  assert.equal(getKey(), "sk-or-v1-abcdef1234");
  assert.equal(((await stat(secretsFile())).mode & 0o777), 0o600);
  const s = status({ enabled: true, model: "" });
  assert.equal(s.hasKey, true);
  assert.equal(s.keyHint, "1234");
  assert.equal(s.model, "voyageai/rerank-3-lite");
  assert.match(s.external, /OpenRouter/);
  assert.ok(!JSON.stringify(s).includes("abcdef"), "the key itself never appears in the status");
  assert.deepEqual(childEnv({ enabled: true, model: "" }), { OPENROUTER_API_KEY: "sk-or-v1-abcdef1234" });
  assert.deepEqual(childEnv({ enabled: false, model: "" }), {}, "no key reaches the child while off");
  setKey("");
  assert.equal(getKey(), null);
  assert.equal(keyHint(null), null);
  assert.match(status({ enabled: true, model: "" }).external, /없음/, "enabled without a key sends nothing");
});

test("rerank: AutoRAG config gets rerank on/off and loses jev/queryDecomposition", async () => {
  const f = join(process.env.ZAEVIS_HOME!, "autorag", "config.json");
  await (await import("node:fs/promises")).mkdir(join(process.env.ZAEVIS_HOME!, "autorag"), { recursive: true });
  await writeFile(f, JSON.stringify({ searchPaths: ["/w"], rerank: { provider: "openrouter" }, jev: { backend: "openrouter" }, queryDecomposition: { model: {} } }));
  assert.equal(applyToAutoragConfig(f, { enabled: true, model: "voyageai/rerank-3-lite" }, true), true);
  let c = JSON.parse(await readFile(f, "utf8"));
  assert.deepEqual(c.rerank, { provider: "openrouter", model: "voyageai/rerank-3-lite", apiKeyEnv: "OPENROUTER_API_KEY", topN: 25 });
  assert.equal("jev" in c, false);
  assert.equal("queryDecomposition" in c, false);
  assert.deepEqual(c.searchPaths, ["/w"], "other settings untouched");
  applyToAutoragConfig(f, { enabled: true, model: "x" }, false);
  c = JSON.parse(await readFile(f, "utf8"));
  assert.equal(c.rerank, false, "enabled but no key → off");
  assert.equal(applyToAutoragConfig(join(process.env.ZAEVIS_HOME!, "nope.json"), { enabled: false, model: "" }, false), false);
});

test("rerank: testKey reports ok / rejected / unreachable without leaking the key", async () => {
  const seen: string[] = [];
  const fake = (async (url: string | URL | Request, init?: RequestInit) => {
    seen.push(String((init?.headers as Record<string, string>).authorization));
    return new Response(JSON.stringify({ data: { label: "zaevis" } }), { status: 200 });
  }) as typeof fetch;
  const ok = await testKey("sk-test-1234", fake);
  assert.deepEqual(ok, { ok: true, message: "연결됨 (zaevis)." });
  assert.equal(seen[0], "Bearer sk-test-1234");
  const rejected = await testKey("bad", (async () => new Response("", { status: 401 })) as typeof fetch);
  assert.equal(rejected.ok, false);
  assert.match(rejected.message, /401/);
  const down = await testKey("k", (async () => { throw new Error("ENOTFOUND"); }) as typeof fetch);
  assert.match(down.message, /ENOTFOUND/);
  assert.equal((await testKey("  ")).ok, false);
});
