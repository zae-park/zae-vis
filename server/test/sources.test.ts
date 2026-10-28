import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { chmod, mkdir, mkdtemp, readFile, readdir, writeFile, utimes } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { redact } from "../src/redact.ts";
import { parseGitLog } from "../src/sources/git.ts";
import { renderSession, summarize, userText } from "../src/sources/claudeCode.ts";
import { enableExtendedHistory, hasExtendedHistory, parseZshHistory, unmetafy, zshrcPath } from "../src/sources/shellHistory.ts";
import { splitByDate } from "../src/sources/command.ts";
import { isStale, labelFor, parseTime, renderPlist } from "../src/schedule.ts";

test("redact masks common secrets but keeps normal text", () => {
  // 토큰 모양은 실행할 때만 붙인다. 소스에 통째로 있으면 공개 저장소 검사가 가짜 값을 비밀로 본다.
  const openai = ["sk-proj-", "abcdefghijklmnop", "1234"].join("");
  const bearer = ["eyJ", "hbGciOiJIUzI1"].join("");
  const apiToken = ["dapi", "01234567", "89abcdef", "01234567", "89abcdef"].join("");
  const password = ["hunter", "22"].join("");
  const urlPassword = ["pw", "123"].join("");
  const s = redact(
    `export OPENAI_API_KEY=${openai} && curl -H 'Authorization: Bearer ${bearer}' https://u:${urlPassword}@host/x --password ${password} ${apiToken}`,
  );
  for (const part of [openai.slice(8), bearer, password, urlPassword, apiToken.slice(4)]) assert.equal(s.includes(part), false);
  assert.match(s, /dapi\*\*\*/);
  assert.match(s, /curl/);
  assert.equal(redact("검색 색인 누락"), "검색 색인 누락");
});

test("parseGitLog reads subject and shortstat", () => {
  const out = "\x1eabc1234567\x1f2026-10-21T10:15:00+09:00\x1f박재\x1ffeat: 정리 분리\n 3 files changed, 40 insertions(+), 2 deletions(-)\n\x1edef9876543\x1f2026-10-21T11:00:00+09:00\x1fbot\x1fdocs\n";
  const c = parseGitLog("repo", out);
  assert.equal(c[0].author, "박재");
  assert.equal(c.length, 2);
  assert.deepEqual([c[0].files, c[0].ins, c[0].del, c[1].files], [3, 40, 2, 0]);
});

test("git source collects every author's commits from a real repo, grouped by day", async () => {
  const root = await mkdtemp(join(tmpdir(), "zv-git-"));
  const repo = join(root, "proj-a");
  await mkdir(repo);
  const g = (...a: string[]) => execFileSync("git", ["-C", repo, ...a], { env: { ...process.env, GIT_AUTHOR_DATE: "2026-10-21T10:00:00", GIT_COMMITTER_DATE: "2026-10-21T10:00:00" } });
  g("init", "-q");
  g("config", "user.email", "me@x.io");
  g("config", "user.name", "me");
  await writeFile(join(repo, "a.txt"), "1");
  g("add", ".");
  g("commit", "-qm", "feat: 첫 커밋 token=abcd1234secret");
  g("-c", "user.email=other@x.io", "commit", "-q", "--allow-empty", "-m", "남의 커밋", "--author", "o <other@x.io>");
  const { gitSource } = await import("../src/sources/git.ts");
  const r = await gitSource.collect({ from: new Date("2026-10-20T00:00:00"), to: new Date("2026-10-22T00:00:00"), settings: { enabled: true, reposRoot: root, depth: 2 }, config: {} as never, log: () => {} });
  assert.deepEqual(Object.keys(r.days), ["2026-10-21"]);
  assert.match(r.days["2026-10-21"], /^## proj-a\n/);
  assert.match(r.days["2026-10-21"], /^- 10:00 `[0-9a-f]{7}` feat: 첫 커밋 token=\*\*\* \(1 files, \+1 −0\) — me$/m);
  assert.match(r.days["2026-10-21"], /^- 10:00 `[0-9a-f]{7}` 남의 커밋 — o$/m);
  assert.match(r.note ?? "", /작성자 2명/);
});

const cc = (o: Record<string, unknown>) => ({ sessionId: "s1234567890", cwd: "/Users/me/jaepark/notes", gitBranch: "main", ...o });

test("claude-code: summarise prompts, files, commands, last answer; skip noise", () => {
  const lines = [
    { type: "ai-title", aiTitle: "노트 정리 분리" },
    cc({ type: "user", timestamp: "2026-10-21T01:00:00Z", message: { role: "user", content: "<system-reminder>x</system-reminder>기록과 수집을 나눠 정리해줘" } }),
    cc({ type: "assistant", timestamp: "2026-10-21T01:01:00Z", message: { content: [{ type: "tool_use", name: "Edit", input: { file_path: "/Users/me/jaepark/notes/notes.md" } }, { type: "tool_use", name: "Bash", input: { command: "pytest -q\necho done" } }] } }),
    cc({ type: "user", timestamp: "2026-10-21T01:02:00Z", message: { content: [{ type: "tool_result", content: "ok" }] } }),
    cc({ type: "user", timestamp: "2026-10-21T01:03:00Z", message: { content: [{ type: "text", text: "Base directory for this skill: /x" }] } }),
    cc({ type: "assistant", timestamp: "2026-10-21T01:05:00Z", message: { content: [{ type: "text", text: "기록 정리를 추가했습니다." }] } }),
    cc({ type: "user", isSidechain: true, timestamp: "2026-10-21T01:06:00Z", message: { content: "subagent prompt" } }),
  ];
  const days = summarize(lines, new Date("2026-10-20T00:00:00Z"), new Date("2026-10-22T00:00:00Z"));
  assert.equal(days.size, 1);
  const s = [...days.values()][0];
  assert.equal(s.title, "노트 정리 분리");
  assert.deepEqual(s.prompts, ["기록과 수집을 나눠 정리해줘"]);
  assert.deepEqual([...s.files], ["/Users/me/jaepark/notes/notes.md"]);
  assert.deepEqual(s.commands, ["pytest -q\necho done"]);
  const md = renderSession(s, "/Users/me");
  assert.match(md, /폴더: `~\/jaepark\/notes` · 브랜치 `main`/);
  assert.match(md, /수정한 파일 \(1\): `~\/jaepark\/notes\/notes.md`/);
  assert.match(md, /`pytest -q`/);
  assert.match(md, /- 요청과 응답 \(\d+\):\n  - 요청: /);
  assert.match(md, /    응답: 기록 정리를 추가했습니다\./);
  assert.doesNotMatch(md, /마지막 응답/);
  assert.equal(userText({ type: "user", message: { content: [{ type: "tool_result" }] } }), null);
});

test("claude-code source reads a projects folder", async () => {
  const root = await mkdtemp(join(tmpdir(), "zv-cc-"));
  await mkdir(join(root, "-Users-me-notes"));
  const now = new Date();
  const line = (o: object) => JSON.stringify(o) + "\n";
  await writeFile(join(root, "-Users-me-notes", "abc.jsonl"), line(cc({ type: "user", timestamp: now.toISOString(), message: { content: "테스트 요청" } })) + "{broken");
  const { claudeCodeSource } = await import("../src/sources/claudeCode.ts");
  const r = await claudeCodeSource.collect({ from: new Date(now.getTime() - 3600e3), to: new Date(now.getTime() + 1000), settings: { enabled: true, projectsDir: root }, config: {} as never, log: () => {} });
  assert.equal(Object.keys(r.days).length, 1);
  assert.match(Object.values(r.days)[0], /테스트 요청/);
});

test("zsh history: extended format, continuation lines, metafied Korean", () => {
  const ko = Buffer.from("echo 한글", "utf8");
  const meta: number[] = [];
  for (const b of ko) if (b >= 0x80) meta.push(0x83, b ^ 0x20); else meta.push(b);
  assert.equal(unmetafy(Buffer.from(meta)), "echo 한글");
  const { entries, extended } = parseZshHistory(": 1792000000:0;git status\n: 1792000100:3;docker run \\\n  -it img\n");
  assert.ok(extended);
  assert.equal(entries[1].command, "docker run \n  -it img");
  assert.equal(parseZshHistory("ls\ncd x\n").extended, false);
});

test("command connector splits output by date markers", () => {
  const out = "intro\n<!-- zaevis:date 2026-10-20 -->\nA\n<!-- zaevis:date 2026-10-21 -->\nB\n";
  assert.deepEqual(splitByDate(out, "2026-10-23"), { "2026-10-23": "intro", "2026-10-20": "A", "2026-10-21": "B" });
});

test("schedule: plist is valid XML with the time; staleness rule", () => {
  const xml = renderPlist({ dailyAt: "18:30", bin: "/Users/me/zaevis/bin/zaevis", path: "/usr/bin:/bin", logFile: "/Users/me/.zaevis/daily.log" });
  assert.match(xml, /<key>Hour<\/key>\s*<integer>18<\/integer>\s*<key>Minute<\/key>\s*<integer>30<\/integer>/);
  assert.match(xml, /<string>--if-stale<\/string>/);
  assert.doesNotMatch(xml, /ZAEVIS_HOME/);
  const home = join(tmpdir(), "label-home");
  assert.equal(labelFor(undefined, home), "io.github.zaepark.zaevis.daily");
  assert.equal(labelFor(join(home, ".zaevis"), home), "io.github.zaepark.zaevis.daily");
  assert.match(labelFor(join(tmpdir(), "zv test"), home), /^io\.github\.zaepark\.zaevis\.daily\.zv-test-[0-9a-f]{6}$/);
  const custom = renderPlist({ dailyAt: "18:30", bin: "/b", path: "/usr/bin", logFile: "/l", env: { ZAEVIS_HOME: "/tmp/zv&test" } });
  assert.match(custom, /<key>ZAEVIS_HOME<\/key>\s*<string>\/tmp\/zv&amp;test<\/string>/);
  assert.throws(() => parseTime("25:00"));
  const at = (s: string) => new Date(s);
  assert.equal(isStale(null, "18:30"), true);
  assert.equal(isStale(at("2026-10-23T18:31:00"), "18:30", at("2026-10-23T20:00:00")), false); // already ran today
  assert.equal(isStale(at("2026-10-22T18:31:00"), "18:30", at("2026-10-23T18:31:00")), true); // today's slot passed
  assert.equal(isStale(at("2026-10-22T18:31:00"), "18:30", at("2026-10-23T09:00:00")), false); // before today's slot
  assert.equal(isStale(at("2026-10-21T09:00:00"), "18:30", at("2026-10-23T09:00:00")), true); // > 36h
});

test("collect(): writes day files, appends for event sources, records state; whisperX via fake binary", async () => {
  const home = await mkdtemp(join(tmpdir(), "zv-home-"));
  const worklog = join(home, "worklog");
  await mkdir(join(worklog, "inbox", "audio"), { recursive: true });
  const exportDir = join(home, "exports");
  await mkdir(exportDir);
  await writeFile(join(exportDir, "주간회의.txt"), "회의 내용");
  await writeFile(join(worklog, "inbox", "audio", "2026-10-21_스탠드업.m4a"), "fake-audio");
  const memoJs = join(home, "memo.js");
  await writeFile(memoJs, "process.stdout.write('<!-- zaevis:date 2026-10-21 -->\\n- 메모 하나\\n');\n");

  // fake whisperx: writes <stem>.txt into --output_dir
  const fake = join(home, "whisperx");
  await writeFile(fake, `#!/bin/sh\nout=""; prev=""; for a in "$@"; do [ "$prev" = "--output_dir" ] && out="$a"; prev="$a"; done\nstem=$(basename "$1"); stem="\${stem%.*}"\necho "전사된 문장 password=abc12345" > "$out/$stem.txt"\n`);
  await chmod(fake, 0o755);

  process.env.ZAEVIS_HOME = join(home, ".zaevis");
  process.env.ZAEVIS_WHISPERX = fake;
  await mkdir(process.env.ZAEVIS_HOME);
  await writeFile(join(process.env.ZAEVIS_HOME, "config.json"), JSON.stringify({ worklogDir: worklog, reposRoot: home }));
  await writeFile(
    join(process.env.ZAEVIS_HOME, "sources.json"),
    JSON.stringify({
      git: { enabled: false },
      "agent-sessions": { enabled: false },
      "shell-history": { enabled: false },
      transcripts: { importDirs: [exportDir] },
      custom: [{ name: "memo", command: `"${process.execPath}" "${memoJs}"` }, { name: "Bad Name!", command: "true" }],
    }),
  );
  const { loadConfig, loadState } = await import("../src/config.ts");
  const { collect, listSources } = await import("../src/sources/index.ts");
  const cfg = loadConfig();
  const report = await collect(cfg, { log: () => {} });
  assert.deepEqual(report.map((r) => [r.name, r.ok]), [["transcripts", true], ["memo", true]]);

  const transcripts = await readdir(join(worklog, "inbox", "transcripts"));
  assert.ok(transcripts.some((f) => /^\d{4}-\d{2}-\d{2}_주간회의\.txt$/.test(f)), String(transcripts));
  const auto = transcripts.find((f) => f.startsWith("2026-10-21_스탠드업"))!;
  const autoText = await readFile(join(worklog, "inbox", "transcripts", auto), "utf8");
  assert.match(autoText, /전사된 문장 password=\*\*\*/);
  assert.ok(existsSync(join(worklog, "processed", "audio", "2026-10-21_스탠드업.m4a")));
  assert.match(await readFile(join(worklog, "sources", "memo", "2026-10-21.md"), "utf8"), /# memo · 2026-10-21[\s\S]*- 메모 하나/);

  // second run: nothing new, transcripts day file keeps earlier lines (append mode)
  const day = (await readdir(join(worklog, "sources", "transcripts")))[0];
  const before = await readFile(join(worklog, "sources", "transcripts", day), "utf8");
  await collect(cfg, { log: () => {} });
  assert.equal(await readFile(join(worklog, "sources", "transcripts", day), "utf8"), before);

  assert.equal(loadState().sources.memo.lastOk, true);
  const names = listSources(cfg).map((s) => s.name);
  assert.deepEqual(names, ["git", "agent-sessions", "shell-history", "transcripts", "memo"]); // invalid custom name skipped

  delete process.env.ZAEVIS_HOME;
  delete process.env.ZAEVIS_WHISPERX;
  void utimes;
});

test("shell-history: enableExtendedHistory appends one line to the zshrc in HOME (or ZDOTDIR), once", async () => {
  const home = await mkdtemp(join(tmpdir(), "zv-home-"));
  const env = { HOME: home };
  assert.equal(zshrcPath(env), join(home, ".zshrc"));
  // no zshrc yet: created with just our line
  let r = await enableExtendedHistory(env);
  assert.deepEqual(r, { file: join(home, ".zshrc"), changed: true });
  assert.equal(await readFile(r.file, "utf8"), "setopt EXTENDED_HISTORY  # zaevis\n");
  // already on: untouched
  r = await enableExtendedHistory(env);
  assert.equal(r.changed, false);
  assert.equal(await readFile(r.file, "utf8"), "setopt EXTENDED_HISTORY  # zaevis\n");
  // an existing file without a trailing newline gets the line on its own line
  await writeFile(join(home, ".zshrc"), "export PATH=$HOME/bin:$PATH\n# setopt EXTENDED_HISTORY (commented out)\nalias ll='ls -l'");
  r = await enableExtendedHistory(env);
  assert.equal(r.changed, true);
  assert.equal(await readFile(r.file, "utf8"), "export PATH=$HOME/bin:$PATH\n# setopt EXTENDED_HISTORY (commented out)\nalias ll='ls -l'\nsetopt EXTENDED_HISTORY  # zaevis\n");
  // ZDOTDIR wins over HOME
  const zdot = await mkdtemp(join(tmpdir(), "zv-zdot-"));
  r = await enableExtendedHistory({ HOME: home, ZDOTDIR: zdot });
  assert.deepEqual(r, { file: join(zdot, ".zshrc"), changed: true });
  // the option in its other spellings counts as on
  for (const t of ["setopt extendedhistory", "setopt SHARE_HISTORY EXTENDED_HISTORY", "  set -o ExtendedHistory  # mine"]) assert.equal(hasExtendedHistory(t), true, t);
  for (const t of ["", "#setopt EXTENDED_HISTORY", "setopt HIST_IGNORE_DUPS", "unsetopt EXTENDED_HISTORY"]) assert.equal(hasExtendedHistory(t), false, JSON.stringify(t));
});
