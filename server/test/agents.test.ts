import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { agentsSource, summarizeChatgpt, summarizeCodex, summarizeGemini } from "../src/sources/agents.ts";

const from = new Date("2026-10-20T00:00:00");
const to = new Date("2026-10-27T00:00:00");

test("agents: Codex rollout JSONL → prompts, last answer, shell commands per day", () => {
  const lines = [
    { timestamp: "2026-10-21T09:00:00Z", type: "session_meta", payload: { id: "sess-1", cwd: "/Users/me/proj" } },
    { timestamp: "2026-10-21T09:01:00Z", type: "response_item", payload: { type: "message", role: "user", content: [{ type: "input_text", text: "<environment_context>x</environment_context>테스트를 고쳐 줘" }] } },
    { timestamp: "2026-10-21T09:02:00Z", type: "response_item", payload: { type: "function_call", name: "shell", arguments: JSON.stringify({ command: ["npm", "test"] }) } },
    { timestamp: "2026-10-21T09:03:00Z", type: "response_item", payload: { type: "message", role: "assistant", content: [{ type: "output_text", text: "고쳤습니다." }] } },
    { timestamp: "2026-10-01T09:03:00Z", type: "response_item", payload: { type: "message", role: "user", content: "오래된 줄" } },
    { garbage: true },
  ];
  const days = summarizeCodex(lines, from, to, "fallback");
  assert.deepEqual([...days.keys()], ["2026-10-21"]);
  const s = days.get("2026-10-21")!;
  assert.equal(s.sessionId, "sess-1");
  assert.equal(s.cwd, "/Users/me/proj");
  assert.deepEqual(s.prompts, ["테스트를 고쳐 줘"]);
  assert.deepEqual(s.commands, ["npm test"]);
  assert.equal(s.lastAnswer, "고쳤습니다.");
  assert.equal(s.title, "테스트를 고쳐 줘");
});

test("agents: Gemini CLI chat JSON → prompts and reply", () => {
  const doc = { sessionId: "g1", startTime: "2026-10-22T10:00:00Z", messages: [
    { type: "user", content: "요약해 줘", timestamp: "2026-10-22T10:00:00Z" },
    { type: "gemini", content: [{ text: "요약입니다." }], timestamp: "2026-10-22T10:00:05Z" },
    { type: "user", content: "창 밖", timestamp: "2026-11-05T10:00:00Z" },
  ] };
  const days = summarizeGemini(doc, from, to, "f");
  assert.deepEqual([...days.keys()], ["2026-10-22"]);
  assert.deepEqual(days.get("2026-10-22")!.prompts, ["요약해 줘"]);
  assert.equal(days.get("2026-10-22")!.lastAnswer, "요약입니다.");
});

test("agents: ChatGPT export conversations.json → one session per conversation per day", () => {
  const conv = [{
    id: "c1", title: "여행 계획", mapping: {
      a: { message: { author: { role: "user" }, create_time: Date.UTC(2026, 9, 23, 1) / 1000, content: { parts: ["제주 3박 일정"] } } },
      b: { message: { author: { role: "assistant" }, create_time: Date.UTC(2026, 9, 23, 1, 1) / 1000, content: { parts: ["1일차 …"] } } },
      c: { message: { author: { role: "system" }, create_time: Date.UTC(2026, 9, 23, 0) / 1000, content: { parts: [""] } } },
    },
  }];
  const days = summarizeChatgpt(conv, from, to);
  assert.deepEqual([...days.keys()], ["2026-10-23"]);
  const s = days.get("2026-10-23")![0];
  assert.equal(s.title, "여행 계획");
  assert.deepEqual(s.prompts, ["제주 3박 일정"]);
  assert.equal(s.lastAnswer, "1일차 …");
});

test("agents: the source merges providers, tags each session with its tool, skips missing folders", async () => {
  const home = await mkdtemp(join(tmpdir(), "zv-agents-"));
  const codexDir = join(home, "codex", "2026", "10", "21");
  await mkdir(codexDir, { recursive: true });
  await writeFile(join(codexDir, "rollout-1.jsonl"), [
    JSON.stringify({ timestamp: "2026-10-21T09:00:00Z", type: "session_meta", payload: { id: "s", cwd: "/w" } }),
    JSON.stringify({ timestamp: "2026-10-21T09:01:00Z", type: "response_item", payload: { type: "message", role: "user", content: "코덱스에서 물어봄" } }),
  ].join("\n"));
  const r = await agentsSource.collect({
    from, to, config: {} as never, log: () => {},
    settings: { enabled: true, claude: false, gemini: true, codex: true, codexDir, geminiDir: join(home, "nope"), chatgptExportDir: "" },
  });
  assert.equal(r.note, "Codex CLI 1개 · Gemini CLI 기록 없음");
  assert.match(r.days["2026-10-21"], /^## Codex CLI · \d\d:\d\d–\d\d:\d\d 코덱스에서 물어봄/m); // times are local
  assert.match(r.days["2026-10-21"], /- 요청과 응답 \(1\):\n  - 요청: 코덱스에서 물어봄/);
  assert.deepEqual(agentsSource.options.map((o) => [o.key, o.kind]), [["claude", "bool"], ["codex", "bool"], ["gemini", "bool"], ["chatgptExportDir", "path"]]);
});
