import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

process.env.ZAEVIS_HOME = await mkdtemp(join(tmpdir(), "zv-digest-state-"));
const { DigestRunner, buildPrompt, checkLogin, cliArgs, detectAgents, findBin, gatherInputs, isFirstMonday, noAgentReason, parseCursorAuth, parseLoggedIn, pickAgent, runOpenRouter, setSection, weeklyDue } = await import("../src/digest.ts");

// Test doubles for agent CLIs: tiny shell scripts that print a version or append one log line.
async function stubCli(dir: string, name: string, body: string): Promise<string> {
  const p = join(dir, name);
  await writeFile(p, `#!/bin/bash\n${body}\n`);
  await chmod(p, 0o755);
  return p;
}

async function worklog(): Promise<string> {
  const w = await mkdtemp(join(tmpdir(), "zv-digest-wl-"));
  await mkdir(join(w, "sources", "git"), { recursive: true });
  await mkdir(join(w, "inbox", "transcripts"), { recursive: true });
  await mkdir(join(w, "projects"), { recursive: true });
  await mkdir(join(w, "log"), { recursive: true });
  await writeFile(join(w, "README.md"), "# worklog\n");
  await writeFile(join(w, ".state.md"), "last_weekly: 2026-10-19\n");
  await writeFile(join(w, "sources", "git", "2026-10-18.md"), "# git · 2026-10-18\n\n## old\n\n- 10:00 `aaaaaaa` old commit — me\n");
  await writeFile(join(w, "sources", "git", "2026-10-25.md"), "# git · 2026-10-25\n\n## notes\n\n- 10:00 `bbbbbbb` feat: 정리 분리 — me\n");
  await writeFile(join(w, "inbox", "transcripts", "2026-10-24_회의.txt"), "색인은 10월 안에 끝내기로 함\n");
  await writeFile(join(w, "projects", "notes.md"), "---\nrepos: [notes]\nstatus: 진행 중\n---\n# 노트\n\n## 현재 상태\n\n예전 상태\n\n## 주요 결정\n\n## 열린 문제\n\n## 링크\n");
  return w;
}

test("digest: detects CLIs on PATH and OpenRouter by key; auto picks the first available", async () => {
  const bins = await mkdtemp(join(tmpdir(), "zv-bins-"));
  await stubCli(bins, "codex", "echo 'codex-cli 0.9.0'");
  const env = { PATH: bins, HOME: bins };
  await mkdir(join(bins, ".codex"));
  await writeFile(join(bins, ".codex", "auth.json"), "{}"); // codex counts as signed in by this file
  assert.equal(findBin("codex", env, [bins]), join(bins, "codex"));
  assert.equal(findBin("gemini", env, [bins]), null);
  const agents = await detectAgents(env, false, [bins]); // only the stub folder, not this Mac's real CLIs
  assert.deepEqual(agents.map((a) => [a.id, a.available, a.loggedIn]), [["claude", false, null], ["codex", true, true], ["cursor", false, null], ["gemini", false, null], ["openrouter", false, null]]);
  assert.equal(agents[1].detail, "codex-cli 0.9.0");
  assert.equal(pickAgent({ agent: "auto", model: "", weekly: true }, agents)?.id, "codex");
  assert.equal(pickAgent({ agent: "claude", model: "", weekly: true }, agents), null, "a chosen but missing agent is not substituted");
  assert.equal(pickAgent({ agent: "auto", model: "", weekly: true }, await detectAgents(env, true, [bins]))?.id, "codex", "a CLI beats the API");
});

test("digest: login detection — claude by `auth status`, codex/gemini by files or env; a signed-out CLI is skipped", async () => {
  const bins = await mkdtemp(join(tmpdir(), "zv-bins-"));
  for (const n of ["claude", "codex", "gemini"]) await stubCli(bins, n, "echo 1.0.0");
  const env = { PATH: bins, HOME: bins };
  const calls: string[][] = [];
  const exec = async (_bin: string, args: string[]) => {
    calls.push(args);
    if (args[0] === "auth") return { code: 0, out: '{\n  "loggedIn": false,\n  "authMethod": "none"\n}\n' };
    return { code: 0, out: "1.0.0\n" };
  };
  const cache = new Map();
  const agents = await detectAgents(env, false, [bins], { exec, cache });
  assert.deepEqual(agents.map((a) => [a.id, a.available, a.loggedIn]), [["claude", true, false], ["codex", true, false], ["cursor", false, null], ["gemini", true, false], ["openrouter", false, null]]);
  assert.equal(agents[0].loginHint, "터미널에서 claude login");
  assert.equal(pickAgent({ agent: "auto", model: "", weekly: true, review: true }, agents), null, "all three installed, none signed in");
  assert.equal(pickAgent({ agent: "claude", model: "", weekly: true, review: true }, agents), null, "an explicitly chosen but signed-out CLI is not used");
  assert.match(noAgentReason(agents), /Claude Code는 설치돼 있지만 로그인되지 않았습니다 \(터미널에서 claude login\)/);
  assert.match(noAgentReason([]), /^쓸 수 있는 에이전트가 없습니다/);

  // cached: a second detect within 10 minutes runs nothing
  const n = calls.length;
  await detectAgents(env, false, [bins], { exec, cache });
  assert.equal(calls.length, n, "version and login answers are cached per binary");
  // expired: runs again, and gemini now has a key in env
  const later = () => Date.now() + 11 * 60_000;
  const again = await detectAgents({ ...env, GEMINI_API_KEY: "k" }, false, [bins], { exec: async (_b, args) => ({ code: 0, out: args[0] === "auth" ? '{"loggedIn":true}' : "1.0.1" }), cache, now: later });
  assert.deepEqual(again.map((a) => [a.id, a.loggedIn]), [["claude", true], ["codex", false], ["cursor", null], ["gemini", true], ["openrouter", null]]);
  assert.equal(again[0].detail, "1.0.1");
  assert.equal(pickAgent({ agent: "auto", model: "", weekly: true, review: true }, again)?.id, "claude");

  // old claude without `auth status`: fall back to a one-turn prompt and read "Not logged in"
  const old = async (_b: string, args: string[]) => (args[0] === "auth" ? { code: 1, out: "error: unknown command 'auth'" } : { code: 1, out: "Not logged in · Please run /login" });
  assert.equal(await checkLogin("claude", join(bins, "claude"), env, old), false);
  const oldOk = async (_b: string, args: string[]) => (args[0] === "auth" ? { code: 1, out: "error: unknown command 'auth'" } : { code: 0, out: "ok" });
  assert.equal(await checkLogin("claude", join(bins, "claude"), env, oldOk), true);
  assert.equal(await checkLogin("claude", join(bins, "claude"), env, async () => ({ code: null, out: "" })), null, "timeout → unknown");
  assert.equal(parseLoggedIn("Checking…\n{\"loggedIn\": true}\n"), true);
  assert.equal(parseLoggedIn("garbage"), null);
  assert.equal(await checkLogin("codex", "", { ...env, OPENAI_API_KEY: "k" }), true);
});

test("digest: prompt, CLI args, due dates", async () => {
  const p = buildPrompt({ worklogDir: "/w", reposRoot: "/r" });
  assert.match(p, /\/w\/README\.md/);
  assert.match(p, /폴더 밖의 파일은/);
  assert.ok(cliArgs("claude", "x").includes("acceptEdits") && cliArgs("claude", "x").includes("Bash(mv:*)"));
  assert.deepEqual(cliArgs("codex", "x").slice(0, 2), ["exec", "--full-auto"]);
  assert.deepEqual(cliArgs("gemini", "x"), ["-p", "x", "--yolo"]);
  assert.deepEqual(cliArgs("cursor", "x"), ["-p", "--force", "--trust", "--output-format", "text", "x"]);
  assert.equal(parseCursorAuth('{"isAuthenticated":true,"status":"authenticated"}'), true);
  assert.equal(parseCursorAuth('{"isAuthenticated":false}'), false);
  assert.equal(isFirstMonday(new Date("2026-11-02T10:00:00")), true);
  assert.equal(isFirstMonday(new Date("2026-11-09T10:00:00")), false);
  const w = await worklog();
  const s = { agent: "auto" as const, model: "", weekly: true };
  assert.equal(weeklyDue(s, w, new Date("2026-10-27T18:30:00")), false, "Tuesday");
  assert.equal(weeklyDue(s, w, new Date("2026-10-26T18:30:00")), true, "Monday, last run 7 days ago");
  assert.equal(weeklyDue({ ...s, weekly: false }, w, new Date("2026-10-26T18:30:00")), false);
});

test("digest: fallback follows the saved order and leaves out a skipped block", () => {
  const agents = (["claude", "codex", "cursor", "gemini"] as const).map((id) => ({ id, title: id, available: true, detail: "", loggedIn: true as boolean | null }));
  const setting = { agent: "auto" as const, model: "", weekly: true, review: true, order: ["cursor", "claude", "codex", "gemini"] as const, skip: ["cursor" as const] };
  assert.equal(pickAgent({ ...setting, order: [...setting.order], skip: [...setting.skip] }, agents)?.id, "claude");
  assert.equal(pickAgent({ agent: "auto", model: "", weekly: true, review: true, order: ["gemini", "cursor", "claude", "codex"], skip: [] }, agents)?.id, "gemini");
});

test("digest: a CLI agent runs in the worklog folder and its report is recorded", async () => {
  const w = await worklog();
  const bins = await mkdtemp(join(tmpdir(), "zv-bins-"));
  const bin = await stubCli(bins, "claude", 'echo "cwd=$(pwd)"; echo "- 10-25 [[notes]] #done 정리 분리 (src: git notes bbbbbbb)" >> log/2026-10.md; echo "로그 1줄 추가"');
  const runner = new DigestRunner({ env: { PATH: bins, HOME: bins } });
  const cfg = { worklogDir: w, reposRoot: "/r" } as never;
  const r = await runner.run(cfg, { agent: "claude", model: "", weekly: true }, { id: "claude", title: "Claude Code", available: true, detail: "x", bin });
  assert.equal(r.ok, true);
  assert.match(r.report, /cwd=\/.*zv-digest-wl/);
  assert.match(r.report, /로그 1줄 추가/);
  assert.match(await readFile(join(w, "log", "2026-10.md"), "utf8"), /정리 분리/);
  assert.equal(runner.status({ agent: "auto", model: "", weekly: true }, w).last?.agent, "claude");
  assert.equal(runner.status({ agent: "auto", model: "", weekly: false }, w).nextWeekly, null);
  const failing = await stubCli(bins, "gemini", "echo boom >&2; exit 2");
  const bad = await runner.run(cfg, { agent: "gemini", model: "", weekly: true }, { id: "gemini", title: "Gemini CLI", available: true, detail: "x", bin: failing });
  assert.equal(bad.ok, false);
  assert.match(bad.report, /boom/);
});

test("digest: OpenRouter path gathers inputs since the last run and applies the model's plan", async () => {
  const w = await worklog();
  const { setKey } = await import("../src/rerank.ts");
  setKey("sk-or-test");
  const inputs = await gatherInputs(w, "2026-10-19");
  assert.deepEqual(inputs.files, ["sources/git/2026-10-25.md", "inbox/transcripts/2026-10-24_회의.txt"], "older sources skipped, inbox always included");
  let seen = "";
  const fakeFetch = (async (_url: string | URL | Request, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body)) as { model: string; messages: Array<{ content: string }> };
    seen = body.model + "|" + body.messages[1].content;
    const plan = {
      logLines: [
        { date: "2026-10-25", projects: ["notes"], tags: ["done"], text: "기록과 수집을 나눠 정리", src: "git notes bbbbbbb" },
        { date: "2026-10-24", projects: ["notes"], tags: ["decision"], text: "색인 10월 내 완료", src: "2026-10-24_회의" },
      ],
      projects: [
        { slug: "notes", currentState: "정리 분리 완료, 색인 진행", decisions: ["색인 10월 내"], openIssues: ["빠뜨린 파일"] },
        { slug: "new-thing", title: "새 프로젝트", currentState: "시작" },
      ],
      processed: ["inbox/transcripts/2026-10-24_회의.txt", "inbox/transcripts/../../README.md"],
      monthlySummary: null,
    };
    return new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify(plan) } }] }), { status: 200 });
  }) as typeof fetch;
  const r = await runOpenRouter({ worklogDir: w }, "test/model", { fetchImpl: fakeFetch, today: new Date("2026-10-26T10:00:00") });
  assert.equal(r.ok, true, r.output);
  assert.match(r.output, /로그 2줄 추가 · 프로젝트 2개 갱신\(notes, new-thing\) · inbox 1개 처리/);
  assert.match(seen, /^test\/model\|/);
  assert.match(seen, /정리 분리/, "the source text reached the model");
  const log = await readFile(join(w, "log", "2026-10.md"), "utf8");
  assert.match(log, /- 10-25 \[\[notes\]\] #done 기록과 수집을 나눠 정리 \(src: git notes bbbbbbb\)/);
  const notes = await readFile(join(w, "projects", "notes.md"), "utf8");
  assert.match(notes, /## 현재 상태\n\n정리 분리 완료, 색인 진행\n\n## 주요 결정\n\n- 색인 10월 내\n\n## 열린 문제\n\n- 빠뜨린 파일\n\n## 링크/);
  assert.match(await readFile(join(w, "projects", "new-thing.md"), "utf8"), /# 새 프로젝트/);
  assert.equal(existsSync(join(w, "inbox", "transcripts", "2026-10-24_회의.txt")), false);
  assert.equal(existsSync(join(w, "processed", "transcripts", "2026-10-24_회의.txt")), true);
  assert.equal(existsSync(join(w, "README.md")), true, "path escapes are ignored");
  assert.equal(await readFile(join(w, ".state.md"), "utf8"), "last_weekly: 2026-10-26\n");
  const again = await runOpenRouter({ worklogDir: w }, "m", { fetchImpl: fakeFetch, today: new Date("2026-10-26T10:00:00") });
  assert.match(again.output, /새 입력이 없습니다/, "nothing newer than today, inbox emptied");
});

test("digest: auto skips a quota failure that wrote nothing, and stops once the worklog changed", async () => {
  const bins = await mkdtemp(join(tmpdir(), "zv-bins-"));
  const claudeBin = await stubCli(bins, "claude", 'echo "You have hit your usage limit" >&2; exit 1');
  const codexBin = await stubCli(bins, "codex", 'echo "- 10-25 [[notes]] #done 다음 서비스 (src: git notes ccccccc)" >> log/2026-10.md; echo "로그 1줄"');
  const claude = { id: "claude" as const, title: "Claude Code", available: true, detail: "x", bin: claudeBin, loggedIn: true };
  const codex = { id: "codex" as const, title: "Codex CLI", available: true, detail: "x", bin: codexBin, loggedIn: true };
  const env = { PATH: bins, HOME: bins };
  const auto = { agent: "auto" as const, model: "", weekly: true, review: false };
  const w = await worklog();
  const hopped = await new DigestRunner({ env }).run({ worklogDir: w, reposRoot: "/r" } as never, auto, claude, [claude, codex]);
  assert.equal(hopped.ok, true);
  assert.equal(hopped.agent, "codex");
  assert.equal(hopped.rail?.find((s) => s.id === "claude")?.state, "quota");
  assert.equal(hopped.rail?.find((s) => s.id === "codex")?.state, "wrote");
  assert.match(await readFile(join(w, "log", "2026-10.md"), "utf8"), /다음 서비스/);

  const wPinned = await worklog();
  const pinned = await new DigestRunner({ env }).run({ worklogDir: wPinned, reposRoot: "/r" } as never, { ...auto, agent: "claude" }, claude, [claude, codex]);
  assert.equal(pinned.ok, false);
  assert.equal(pinned.agent, "claude");
  assert.equal(existsSync(join(wPinned, "log", "2026-10.md")), false);

  const wrote = await mkdtemp(join(tmpdir(), "zv-bins-"));
  const claudeWrote = await stubCli(wrote, "claude", 'echo "- 10-25 [[notes]] #done 쓴 뒤 할당량 (src: git notes ddddddd)" >> log/2026-10.md; echo "You have hit your usage limit" >&2; exit 1');
  const codexNo = await stubCli(wrote, "codex", 'echo SHOULD-NOT >> log/2026-10.md; echo no');
  const w2 = await worklog();
  const stopped = await new DigestRunner({ env: { PATH: wrote, HOME: wrote } }).run(
    { worklogDir: w2, reposRoot: "/r" } as never,
    auto,
    { ...claude, bin: claudeWrote },
    [{ ...claude, bin: claudeWrote }, { ...codex, bin: codexNo }],
  );
  assert.equal(stopped.ok, false);
  assert.equal(stopped.agent, "claude");
  const body = await readFile(join(w2, "log", "2026-10.md"), "utf8");
  assert.match(body, /쓴 뒤 할당량/);
  assert.doesNotMatch(body, /SHOULD-NOT/);
});

test("digest: setSection replaces or appends", () => {
  assert.equal(setSection("# T\n\n## A\n\nold\n\n## B\n\nb\n", "A", "new"), "# T\n\n## A\n\nnew\n\n## B\n\nb\n");
  assert.match(setSection("# T\n", "C", "c"), /# T\n\n## C\n\nc\n$/);
});
