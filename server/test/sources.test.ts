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
import { parseZshHistory, unmetafy } from "../src/sources/shellHistory.ts";
import { splitByDate } from "../src/sources/command.ts";
import { isStale, parseTime, renderPlist } from "../src/schedule.ts";

test("redact masks common secrets but keeps normal text", () => {
  const s = redact("export OPENAI_API_KEY=sk-proj-abcdefghijklmnop1234 && curl -H 'Authorization: Bearer eyJhbGciOiJIUzI1' https://u:pw123@host/x --password hunter22 dapi-example");
  assert.doesNotMatch(s, /abcdefghijklmnop1234|eyJhbGciOiJIUzI1|hunter22|pw123|dapi0123456789abcdef/);
  assert.match(s, /curl/);
  assert.equal(redact("GA4 캠페인 매핑 누락"), "GA4 캠페인 매핑 누락");
});

test("parseGitLog reads subject and shortstat", () => {
  const out = "\x1eabc1234567\x1f2026-10-21T10:15:00+09:00\x1ffeat: 채점 분리\n 3 files changed, 40 insertions(+), 2 deletions(-)\n\x1edef9876543\x1f2026-10-21T11:00:00+09:00\x1fdocs\n";
  const c = parseGitLog("repo", out);
  assert.equal(c.length, 2);
  assert.deepEqual([c[0].files, c[0].ins, c[0].del, c[1].files], [3, 40, 2, 0]);
});

test("git source collects my commits from a real repo, grouped by day", async () => {
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
  const r = await gitSource.collect({ from: new Date("2026-10-20T00:00:00"), to: new Date("2026-10-22T00:00:00"), settings: { enabled: true, reposRoot: root, authorEmail: "me@x.io", depth: 2 }, config: {} as never, log: () => {} });
  assert.deepEqual(Object.keys(r.days), ["2026-10-21"]);
  assert.match(r.days["2026-10-21"], /## proj-a\n\n- 10:00 `[0-9a-f]{7}` feat: 첫 커밋 token=\*\*\* \(1 files, \+1 −0\)/);
  assert.doesNotMatch(r.days["2026-10-21"], /남의 커밋/);
});

const cc = (o: Record<string, unknown>) => ({ sessionId: "s1234567890", cwd: "/Users/me/jaepark/roas", gitBranch: "main", ...o });

test("claude-code: summarise prompts, files, commands, last answer; skip noise", () => {
  const lines = [
    { type: "ai-title", aiTitle: "ROAS 채점 분리" },
    cc({ type: "user", timestamp: "2026-10-21T01:00:00Z", message: { role: "user", content: "<system-reminder>x</system-reminder>광고와 결제를 분리해서 채점해줘" } }),
    cc({ type: "assistant", timestamp: "2026-10-21T01:01:00Z", message: { content: [{ type: "tool_use", name: "Edit", input: { file_path: "/Users/me/jaepark/roas/score.py" } }, { type: "tool_use", name: "Bash", input: { command: "pytest -q\necho done" } }] } }),
    cc({ type: "user", timestamp: "2026-10-21T01:02:00Z", message: { content: [{ type: "tool_result", content: "ok" }] } }),
    cc({ type: "user", timestamp: "2026-10-21T01:03:00Z", message: { content: [{ type: "text", text: "Base directory for this skill: /x" }] } }),
    cc({ type: "assistant", timestamp: "2026-10-21T01:05:00Z", message: { content: [{ type: "text", text: "분리 채점을 추가했습니다." }] } }),
    cc({ type: "user", isSidechain: true, timestamp: "2026-10-21T01:06:00Z", message: { content: "subagent prompt" } }),
  ];
  const days = summarize(lines, new Date("2026-10-20T00:00:00Z"), new Date("2026-10-22T00:00:00Z"));
  assert.equal(days.size, 1);
  const s = [...days.values()][0];
  assert.equal(s.title, "ROAS 채점 분리");
  assert.deepEqual(s.prompts, ["광고와 결제를 분리해서 채점해줘"]);
  assert.deepEqual([...s.files], ["/Users/me/jaepark/roas/score.py"]);
  assert.deepEqual(s.commands, ["pytest -q\necho done"]);
  const md = renderSession(s, "/Users/me");
  assert.match(md, /폴더: `~\/jaepark\/roas` · 브랜치 `main`/);
  assert.match(md, /수정한 파일 \(1\): `~\/jaepark\/roas\/score.py`/);
  assert.match(md, /`pytest -q`/);
  assert.match(md, /마지막 응답: 분리 채점을 추가했습니다\./);
  assert.equal(userText({ type: "user", message: { content: [{ type: "tool_result" }] } }), null);
});

test("claude-code source reads a projects folder", async () => {
  const root = await mkdtemp(join(tmpdir(), "zv-cc-"));
  await mkdir(join(root, "-Users-me-roas"));
  const now = new Date();
  const line = (o: object) => JSON.stringify(o) + "\n";
  await writeFile(join(root, "-Users-me-roas", "abc.jsonl"), line(cc({ type: "user", timestamp: now.toISOString(), message: { content: "테스트 요청" } })) + "{broken");
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

  // fake whisperx: writes <stem>.txt into --output_dir
  const fake = join(home, "whisperx");
  await writeFile(fake, `#!/bin/sh\nout=""; prev=""; for a in "$@"; do [ "$prev" = "--output_dir" ] && out="$a"; prev="$a"; done\nstem=$(basename "$1"); stem="\${stem%.*}"\necho "전사된 문장 password=abc12345" > "$out/$stem.txt"\n`);
  await chmod(fake, 0o755);

  process.env.ZAEVIS_HOME = join(home, ".zaevis");
  process.env.ZAEVIS_WHISPERX = fake;
  await mkdir(process.env.ZAEVIS_HOME);
  await writeFile(join(process.env.ZAEVIS_HOME, "config.json"), JSON.stringify({ worklogDir: worklog, reposRoot: home, authorEmail: "me@x.io" }));
  await writeFile(
    join(process.env.ZAEVIS_HOME, "sources.json"),
    JSON.stringify({
      git: { enabled: false },
      "claude-code": { enabled: false },
      "shell-history": { enabled: false },
      transcripts: { importDirs: [exportDir] },
      custom: [{ name: "memo", command: "printf '<!-- zaevis:date 2026-10-21 -->\\n- 메모 하나\\n'" }, { name: "Bad Name!", command: "true" }],
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
  assert.deepEqual(names, ["git", "claude-code", "shell-history", "transcripts", "memo"]); // invalid custom name skipped

  delete process.env.ZAEVIS_HOME;
  delete process.env.ZAEVIS_WHISPERX;
  void utimes;
});
