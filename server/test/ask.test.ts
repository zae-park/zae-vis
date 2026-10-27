import assert from "node:assert/strict";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";

process.env.ZAEVIS_HOME = await mkdtemp(join(tmpdir(), "zv-ask-state-"));
const { AskRunner, askCliArgs, buildAskPrompt, cleanAnswer, pickSources } = await import("../src/ask.ts");
const { createApp } = await import("../src/app.ts");
const { normalizeSearch } = await import("../src/autorag.ts");
const { Worklog } = await import("../src/worklog.ts");
import type { SearchBackend } from "../src/autorag.ts";
import type { AgentInfo } from "../src/digest.ts";
import type { Exec } from "../src/ask.ts";

const RAW = {
  results: [
    { path: "/w/sources/git/2026-10-26.md", score: 1, content: "# git · 2026-10-26\n\n## zaevis\n\n- 11:17 `abc1234` 검색 결과 맥락: 출처·날짜·문단 (3 files) — 박재\n- 12:00 `def5678` 로컬 임베딩 켬 — 박재\n" },
    { path: "/w/log/2026-10.md", score: 0.6, content: "- 10-25 [[zaevis]] #decision 검색은 하이브리드 랭킹까지, 답 쓰기는 나중에 (src: 세션)\n" },
    { path: "/w/projects/old.md", score: 0.05, content: "# 옛 프로젝트\n\n## 현재 상태\n\n끝남\n" },
  ],
};

const searchCalls: Array<[string, number, number | undefined]> = [];
const fakeSearch: SearchBackend = {
  async status() {
    return {};
  },
  async refresh() {
    return {};
  },
  async search(query, topK, passageChars) {
    searchCalls.push([query, topK, passageChars]);
    return normalizeSearch(query, query === "없는것" ? { results: [] } : RAW, ["/w"], passageChars);
  },
  async close() {},
};

const claude: AgentInfo = { id: "claude", title: "Claude Code", available: true, detail: "2.1", bin: "/bin/claude" };
const codex: AgentInfo = { id: "codex", title: "Codex CLI", available: true, detail: "0.9", bin: "/bin/codex" };

test("ask: sources skip weak hits and keep the hit's labels; the prompt numbers them", () => {
  const r = normalizeSearch("검색 맥락", RAW, ["/w"], 1000);
  const sources = pickSources(r.hits, 10);
  assert.deepEqual(sources.map((s) => [s.n, s.path]), [[1, "sources/git/2026-10-26.md"], [2, "log/2026-10.md"]], "the 0.05 hit is weak and dropped");
  assert.equal(sources[0].label, "2026-10-26 · git 커밋 · zaevis · 박재");
  assert.match(sources[0].passage, /검색 결과 맥락/);
  const p = buildAskPrompt("검색 맥락은 언제 했지?", sources);
  assert.match(p, /질문: 검색 맥락은 언제 했지\?/);
  assert.match(p, /\[1\] \(2026-10-26 · git 커밋 · zaevis · 박재\) sources\/git\/2026-10-26\.md\n/);
  assert.match(p, /\[2\] \(2026-10 · 한 줄 기록\)/);
  assert.match(p, /근거를 찾지 못했습니다/);
  assert.deepEqual(pickSources(r.hits.filter((h) => h.weak), 10).length, 1, "only weak hits: they are kept rather than answering from nothing");
});

test("ask: CLIs are invoked read-only", () => {
  const a = askCliArgs("claude", "p");
  assert.ok(a.includes("--tools") && a[a.indexOf("--tools") + 1] === "" && a.includes("--max-turns"));
  assert.ok(!a.includes("--allowedTools") && !a.includes("--permission-mode"));
  const c = askCliArgs("codex", "p", { outFile: "/t/a.md" });
  assert.deepEqual(c, ["exec", "--sandbox", "read-only", "--skip-git-repo-check", "-o", "/t/a.md", "p"]);
  assert.deepEqual(askCliArgs("gemini", "p"), ["-p", "p"]);
  assert.equal(cleanAnswer("Loaded cached credentials.\n답입니다 [1]\n"), "답입니다 [1]");
});

test("ask: a CLI agent answers from the prompt in the worklog folder; one question at a time", async () => {
  const execCalls: Array<{ bin: string; args: string[]; cwd: string }> = [];
  let release: () => void = () => {};
  const exec: Exec = async (bin, args, cwd) => {
    execCalls.push({ bin, args, cwd });
    await new Promise<void>((r) => (release = r));
    return { ok: true, stdout: "검색 맥락은 10월 26일에 넣었다 [1]. 답 쓰기는 미뤘다 [2].\n", stderr: "" };
  };
  const runner = new AskRunner({ exec });
  const common = { search: fakeSearch, setting: { model: "" }, worklogDir: "/w" };
  const first = runner.ask("검색 맥락은 언제 했지?", { ...common, agent: claude, topK: 8 });
  await new Promise((r) => setTimeout(r, 10));
  assert.equal(runner.status().running?.q, "검색 맥락은 언제 했지?");
  const busy = await runner.ask("다른 질문", { ...common, agent: claude });
  assert.equal(busy.ok, false);
  assert.equal(!busy.ok && busy.error, "busy");
  release();
  const r = await first;
  assert.equal(r.ok, true);
  if (!r.ok) return;
  assert.equal(r.result.answer, "검색 맥락은 10월 26일에 넣었다 [1]. 답 쓰기는 미뤘다 [2].");
  assert.equal(r.result.agent, "claude");
  assert.equal(r.result.sources.length, 2);
  assert.deepEqual(searchCalls.at(-1), ["검색 맥락은 언제 했지?", 13, 1000], "topK + 5 for weak-hit slack, longer passages");
  assert.equal(execCalls[0].bin, "/bin/claude");
  assert.equal(execCalls[0].cwd, "/w");
  assert.match(execCalls[0].args[1], /^아래 발췌는/);
  assert.equal(runner.status().running, null);
  assert.equal(runner.status().last?.q, "검색 맥락은 언제 했지?");

  const failing: Exec = async () => ({ ok: false, stdout: "", stderr: "Not logged in\nRun claude login" });
  const bad = await new AskRunner({ exec: failing }).ask("x", { ...common, agent: claude });
  assert.equal(bad.ok, false);
  assert.match(!bad.ok ? bad.message : "", /Claude Code 실행 실패: Not logged in \/ Run claude login/);

  const none = await new AskRunner({ exec }).ask("x", { ...common, agent: null });
  assert.equal(!none.ok && none.error, "no_agent");
  const empty = await new AskRunner({ exec }).ask("없는것", { ...common, agent: claude });
  assert.equal(!empty.ok && empty.error, "no_hits");
});

test("ask: Codex's answer is read from its output file", async () => {
  const { writeFile } = await import("node:fs/promises");
  const exec: Exec = async (_bin, args) => {
    const out = args[args.indexOf("-o") + 1];
    await writeFile(out, "코덱스의 답 [1]\n");
    return { ok: true, stdout: "[2026-10-27] thinking…\nprogress log", stderr: "" };
  };
  const r = await new AskRunner({ exec }).ask("q", { search: fakeSearch, agent: codex, setting: { model: "" }, worklogDir: "/w" });
  assert.equal(r.ok && r.result.answer, "코덱스의 답 [1]");
});

test("ask: OpenRouter path sends the prompt as one user message", async () => {
  const { setKey } = await import("../src/rerank.ts");
  setKey("sk-or-test");
  let seen: { model: string; messages: Array<{ role: string; content: string }> } | null = null;
  const fakeFetch = (async (_url: string | URL | Request, init?: RequestInit) => {
    seen = JSON.parse(String(init?.body));
    return new Response(JSON.stringify({ choices: [{ message: { content: "오픈라우터의 답 [1][2]" } }] }), { status: 200 });
  }) as typeof fetch;
  const or: AgentInfo = { id: "openrouter", title: "OpenRouter API", available: true, detail: "키" };
  const r = await new AskRunner({ fetchImpl: fakeFetch }).ask("q", { search: fakeSearch, agent: or, setting: { model: "test/model" }, worklogDir: "/w" });
  assert.equal(r.ok && r.result.answer, "오픈라우터의 답 [1][2]");
  assert.equal(seen!.model, "test/model");
  assert.equal(seen!.messages.length, 1);
  assert.match(seen!.messages[0].content, /질문: q/);
  setKey("");
});

// ── HTTP ───────────────────────────────────────────────────────────────────────

let server: Server;
let base: string;
let agent: AgentInfo | null = claude;
const runner = new AskRunner({ exec: async () => ({ ok: true, stdout: "HTTP 답 [1]", stderr: "" }) });

before(async () => {
  const root = await mkdtemp(join(tmpdir(), "zv-ask-wl-"));
  server = createApp({
    worklog: new Worklog(root),
    search: fakeSearch,
    ask: {
      status: async () => ({ ...runner.status(), agents: [claude], chosen: agent?.id ?? null, setting: { agent: "auto", model: "" } }),
      run: (q, topK) => runner.ask(q, { search: fakeSearch, agent, setting: { model: "" }, worklogDir: root, topK }),
    },
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(() => server.close());

const post = async (body: unknown) => {
  const r = await fetch(base + "/api/ask", { method: "POST", headers: { "content-type": "application/json", "x-zaevis": "1" }, body: JSON.stringify(body) });
  return { status: r.status, body: await r.json() };
};

test("ask: POST /api/ask answers with sources; GET reports agents and the last answer; 409 without an agent", async () => {
  assert.equal((await post({})).status, 400);
  const r = await post({ q: "검색 맥락?", topK: 3 });
  assert.equal(r.status, 200);
  assert.equal(r.body.answer, "HTTP 답 [1]");
  assert.equal(r.body.agent, "claude");
  assert.deepEqual(Object.keys(r.body.sources[0]), ["n", "path", "label", "passage"]);
  assert.ok(typeof r.body.ms === "number");
  const st = await (await fetch(base + "/api/ask")).json();
  assert.equal(st.chosen, "claude");
  assert.equal(st.last.q, "검색 맥락?");
  assert.equal(st.running, null);
  assert.equal((await post({ q: "없는것" })).status, 404);
  agent = null;
  const none = await post({ q: "x" });
  assert.equal(none.status, 409);
  assert.equal(none.body.error, "no_agent");
  assert.match(none.body.message, /Claude Code·Codex·Gemini/);
  assert.equal((await fetch(base + "/api/ask/other")).status, 404);
});
