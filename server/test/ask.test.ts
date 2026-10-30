import assert from "node:assert/strict";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";

process.env.ZAEVIS_HOME = await mkdtemp(join(tmpdir(), "zv-ask-state-"));
const { AskRunner, ConversationStore, askCliArgs, buildAskPrompt, cleanAnswer, pickSources, searchQueryFor } = await import("../src/ask.ts");
const { quotaReason } = await import("../src/rail.ts");
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
  assert.ok(askCliArgs("cursor", "p").includes("--mode") && askCliArgs("cursor", "p").includes("ask"));
  assert.deepEqual(askCliArgs("cursor", "p"), ["-p", "--mode", "ask", "--trust", "--output-format", "text", "p"]);
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
      run: (q, topK, conversationId) => runner.ask(q, { search: fakeSearch, agent, setting: { model: "" }, worklogDir: root, topK, conversationId }),
      conversation: (id) => runner.store.get(id),
      remove: (id) => runner.store.remove(id),
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

test("ask: a follow-up continues the conversation — history in the prompt, short question searched with the previous one", async () => {
  const prompts: string[] = [];
  const exec: Exec = async (_bin, args) => {
    prompts.push(args[1]);
    return { ok: true, stdout: `답 ${prompts.length} [1]`, stderr: "" };
  };
  const store = new ConversationStore(await mkdtemp(join(tmpdir(), "zv-ask-conv-")));
  const runner = new AskRunner({ exec, store });
  const common = { search: fakeSearch, setting: { model: "" }, worklogDir: "/w", agent: claude };
  const first = await runner.ask("검색 맥락은 언제 넣었지?", common);
  assert.ok(first.ok);
  if (!first.ok) return;
  assert.equal(first.result.turn, 0);
  assert.match(first.result.conversationId, /^\d{8}-\d{6}/);
  assert.doesNotMatch(prompts[0], /이전 대화/);

  searchCalls.length = 0;
  const second = await runner.ask("그건 왜?", { ...common, conversationId: first.result.conversationId });
  assert.ok(second.ok);
  if (!second.ok) return;
  assert.equal(second.result.conversationId, first.result.conversationId);
  assert.equal(second.result.turn, 1);
  assert.equal(searchCalls[0][0], "검색 맥락은 언제 넣었지? 그건 왜?", "a short follow-up is searched with the previous question");
  assert.match(prompts[1], /이전 대화[\s\S]*사용자: 검색 맥락은 언제 넣었지\?\n답: 답 1 \[1\]/);
  assert.match(prompts[1], /질문: 그건 왜\?/);

  const conv = store.get(first.result.conversationId)!;
  assert.equal(conv.title, "검색 맥락은 언제 넣었지?");
  assert.equal(conv.turns.length, 2);
  assert.deepEqual(store.list().map((c) => [c.id, c.turns]), [[conv.id, 2]]);
  assert.equal(runner.status().conversations.length, 1);

  // an unknown id starts a fresh conversation instead of failing
  const third = await runner.ask("긴 질문은 혼자 검색된다 그렇지?", { ...common, conversationId: "20200101-000000" });
  assert.ok(third.ok && third.result.conversationId !== conv.id && third.result.turn === 0);
  assert.equal(searchCalls.at(-1)![0], "긴 질문은 혼자 검색된다 그렇지?");
  assert.equal(searchQueryFor("짧다", "앞 질문"), "앞 질문 짧다");
  assert.equal(store.remove(conv.id), true);
  assert.equal(store.get(conv.id), null);
  assert.throws(() => store.get("../x"));
});

test("ask: auto retries the next agent only on quota; a pinned agent and other failures stay put", async () => {
  assert.equal(quotaReason("Not logged in\nRun claude login"), null);
  assert.equal(quotaReason("모델이 빈 답을 돌려줬습니다."), null);
  assert.equal(quotaReason("[시간 초과]"), null);
  assert.match(quotaReason("progress\nYou have hit your usage limit") ?? "", /hit your usage limit/);
  assert.match(quotaReason("You've hit your weekly limit · resets 7am (Asia/Seoul)") ?? "", /weekly limit/);
  assert.match(quotaReason("You've hit your session limit · resets 7:20pm (Asia/Seoul)") ?? "", /session limit/);
  assert.match(quotaReason("OpenRouter HTTP 429: rate limit") ?? "", /429/);

  const calls: string[] = [];
  const exec: Exec = async (bin) => {
    calls.push(bin);
    if (bin.endsWith("claude")) return { ok: false, stdout: "", stderr: "You have hit your usage limit" };
    return { ok: true, stdout: "다음이 쓴 답 [1]", stderr: "" };
  };
  const agents = [claude, codex];
  const base = { search: fakeSearch, worklogDir: "/w", agent: claude, agents };
  const hopped = await new AskRunner({ exec }).ask("q", { ...base, setting: { agent: "auto", model: "" } });
  assert.equal(hopped.ok, true);
  if (!hopped.ok) return;
  assert.equal(hopped.result.agent, "codex");
  assert.equal(hopped.result.answer, "다음이 쓴 답 [1]");
  assert.deepEqual(calls, ["/bin/claude", "/bin/codex"]);
  assert.equal(hopped.result.rail.find((s) => s.id === "claude")?.state, "quota");
  assert.equal(hopped.result.rail.find((s) => s.id === "codex")?.state, "wrote");

  calls.length = 0;
  const pinned = await new AskRunner({ exec }).ask("q", { ...base, setting: { agent: "claude", model: "" } });
  assert.equal(pinned.ok, false);
  assert.deepEqual(calls, ["/bin/claude"]);

  calls.length = 0;
  const crashed: Exec = async (bin) => {
    calls.push(bin);
    if (bin.endsWith("claude")) return { ok: false, stdout: "", stderr: "You have hit your usage limit" };
    return { ok: false, stdout: "", stderr: "segfault" };
  };
  const stopped = await new AskRunner({ exec: crashed }).ask("q", { ...base, setting: { agent: "auto", model: "" } });
  assert.equal(stopped.ok, false);
  assert.match(!stopped.ok ? stopped.message : "", /segfault/);
  assert.equal(!stopped.ok ? stopped.rail?.find((s) => s.id === "codex")?.state : "", "error");
  assert.deepEqual(calls, ["/bin/claude", "/bin/codex"]);
});

test("ask: a weekly-limit line printed as the answer still falls through to Cursor", async () => {
  const cursor: AgentInfo = { id: "cursor", title: "Cursor", available: true, detail: "1", bin: "/bin/cursor-agent", loggedIn: true };
  const calls: string[] = [];
  const exec: Exec = async (bin) => {
    calls.push(bin);
    if (bin.endsWith("claude")) return { ok: true, stdout: "You've hit your weekly limit · resets 7am (Asia/Seoul)", stderr: "" };
    return { ok: true, stdout: "Cursor가 쓴 답 [1]", stderr: "" };
  };
  const hopped = await new AskRunner({ exec }).ask("q", {
    search: fakeSearch,
    worklogDir: "/w",
    agent: claude,
    agents: [claude, cursor],
    setting: { agent: "auto", model: "" },
  });
  assert.equal(hopped.ok, true);
  if (!hopped.ok) return;
  assert.equal(hopped.result.agent, "cursor");
  assert.equal(hopped.result.answer, "Cursor가 쓴 답 [1]");
  assert.equal(hopped.result.rail.find((s) => s.id === "claude")?.state, "quota");
  assert.equal(hopped.result.rail.find((s) => s.id === "cursor")?.state, "wrote");
  assert.deepEqual(calls, ["/bin/claude", "/bin/cursor-agent"]);

  calls.length = 0;
  const kept: Exec = async (bin) => {
    calls.push(bin);
    return { ok: true, stdout: `주간 한도를 weekly limit 이라고 적습니다 [1]. ${"가".repeat(200)}`, stderr: "" };
  };
  const stayed = await new AskRunner({ exec: kept }).ask("q", {
    search: fakeSearch,
    worklogDir: "/w",
    agent: claude,
    agents: [claude, cursor],
    setting: { agent: "auto", model: "" },
  });
  assert.equal(stayed.ok, true);
  if (!stayed.ok) return;
  assert.equal(stayed.result.agent, "claude");
  assert.deepEqual(calls, ["/bin/claude"]);
});

test("ask: GET /api/ask/:id returns a conversation and DELETE removes it", async () => {
  agent = claude;
  const r = await post({ q: "대화 테스트" });
  assert.equal(r.status, 200);
  const id = r.body.conversationId as string;
  const got = await (await fetch(`${base}/api/ask/${id}`)).json();
  assert.equal(got.turns.length, 1);
  assert.equal(got.title, "대화 테스트");
  const st = await (await fetch(base + "/api/ask")).json();
  assert.ok(st.conversations.some((c: { id: string }) => c.id === id));
  const del = await fetch(`${base}/api/ask/${id}`, { method: "DELETE", headers: { "x-zaevis": "1" } });
  assert.equal(del.status, 200);
  assert.equal((await fetch(`${base}/api/ask/${id}`)).status, 404);
});
