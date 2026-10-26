import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

process.env.ZAEVIS_HOME = await mkdtemp(join(tmpdir(), "zv-setup-state-"));
const { excludeFromGit, parseSetupArgs, runSetup, which } = await import("../src/setup.ts");
const { renderWinTask } = await import("../src/schedule.ts");

test("setup: parses the wizard's flags, ignores the retired e-mail ones", () => {
  const o = parseSetupArgs(["--yes", "--skip-refresh", "--worklog", "/w", "--repos", "/r", "--email", "x@y", "--any-author", "--daily-at", "07:00", "--disable", "git", "--disable", "shell-history", "--no-schedule"]);
  assert.deepEqual(o, { disabled: ["git", "shell-history"], skipRefresh: true, worklogDir: "/w", reposRoot: "/r", dailyAt: "07:00", schedule: false });
  assert.throws(() => parseSetupArgs(["--bogus"]), /알 수 없는 옵션/);
});

test("setup: creates the worklog tree, templates, config and state without AutoRAG or a schedule", async () => {
  const home = await mkdtemp(join(tmpdir(), "zv-setup-home-"));
  const lines: string[] = [];
  const root = join(import.meta.dirname, "..", "..");
  await runSetup({ worklogDir: join(home, "worklog"), reposRoot: home, dailyAt: "18:30", disabled: ["shell-history"], autorag: false, schedule: false, skipRefresh: true }, { root, home, log: (l) => lines.push(l) });
  const w = join(home, "worklog");
  for (const d of ["inbox/transcripts", "inbox/audio", "processed/audio", "log", "projects", "summaries", "sources"]) assert.ok(existsSync(join(w, d)), d);
  assert.match(await readFile(join(w, "README.md"), "utf8"), new RegExp(home.replaceAll("\\", "\\\\")), "template placeholders filled");
  assert.ok(existsSync(join(w, "projects", "_template.md")));
  assert.match(await readFile(join(w, ".state.md"), "utf8"), /^last_weekly: \d{4}-\d{2}-\d{2}\n$/);
  const cfg = JSON.parse(await readFile(join(process.env.ZAEVIS_HOME!, "config.json"), "utf8"));
  assert.equal(cfg.worklogDir, w);
  assert.equal(cfg.dailyAt, "18:30");
  const sources = JSON.parse(await readFile(join(process.env.ZAEVIS_HOME!, "sources.json"), "utf8"));
  assert.deepEqual(sources, { "shell-history": { enabled: false }, custom: [] });
  assert.ok(existsSync(join(process.env.ZAEVIS_HOME!, "weekly-task-prompt.md")));
  const state = JSON.parse(await readFile(join(process.env.ZAEVIS_HOME!, "state.json"), "utf8"));
  assert.equal(state.daily.index, "첫 수집은 앱이 진행", "skip-refresh pre-marks today so launchd's RunAtLoad does not collect twice");
  assert.ok(lines.some((l) => l.startsWith("1) worklog 폴더")));
  // re-run: nothing overwritten, existing files reported as skipped
  const before = await readFile(join(w, "README.md"), "utf8");
  await writeFile(join(w, "README.md"), before + "\n내가 고친 줄\n");
  lines.length = 0;
  await runSetup({ worklogDir: w, reposRoot: home, autorag: false, schedule: false }, { root, home, log: (l) => lines.push(l) });
  assert.match(await readFile(join(w, "README.md"), "utf8"), /내가 고친 줄/);
  assert.ok(lines.some((l) => l.includes("(있음, 건너뜀)")));
});

test("setup: keeps the worklog out of a repository that contains it", async () => {
  const repo = await mkdtemp(join(tmpdir(), "zv-setup-repo-"));
  execFileSync("git", ["-C", repo, "init", "-q"]);
  const w = join(repo, "worklog");
  await mkdir(w);
  const lines: string[] = [];
  excludeFromGit([w, join(repo, "CLAUDE.md")], [w, repo], (l) => lines.push(l));
  const ex = await readFile(join(repo, ".git", "info", "exclude"), "utf8");
  assert.match(ex, /^\/worklog$/m);
  assert.match(ex, /^\/CLAUDE\.md$/m);
  excludeFromGit([w], [w], (l) => lines.push(l));
  assert.equal((await readFile(join(repo, ".git", "info", "exclude"), "utf8")).split("/worklog").length, 2, "added once");
});

test("setup: which() looks on PATH; Windows task script carries the state folder", () => {
  assert.ok(which("node"));
  assert.equal(which("definitely-not-a-binary-zv"), null);
  const s = renderWinTask({ bin: "C:\\zaevis\\bin\\zaevis.cmd", stateHome: "C:\\Users\\me\\.zaevis", logFile: "C:\\Users\\me\\.zaevis\\daily.log" });
  assert.match(s, /^@echo off\r\nset "ZAEVIS_HOME=C:\\Users\\me\\.zaevis"\r\n"C:\\zaevis\\bin\\zaevis.cmd" daily --if-stale >> "C:\\Users\\me\\.zaevis\\daily.log" 2>&1\r\n$/);
  assert.doesNotMatch(renderWinTask({ bin: "b", logFile: "l" }), /ZAEVIS_HOME/);
});
