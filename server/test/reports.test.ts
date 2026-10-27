import assert from "node:assert/strict";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";

process.env.ZAEVIS_HOME = await mkdtemp(join(tmpdir(), "zv-reports-state-"));
const {
  ReportRunner, buildReportPrompt, defaultPeriod, dueReports, gatherReportInputs, isValidPeriod, isoWeek, isoWeekStart, listReports, mergeReportsSetting,
  normalizeReportsSetting, periodRange, readReport, reportPath, DEFAULT_REPORTS,
} = await import("../src/reports.ts");
const { loadState } = await import("../src/config.ts");
const { createApp } = await import("../src/app.ts");
const { Worklog } = await import("../src/worklog.ts");
import type { SearchBackend } from "../src/autorag.ts";
import type { AgentInfo } from "../src/digest.ts";
import type { Exec } from "../src/ask.ts";
import type { ReportsSetting } from "../src/reports.ts";

const at = (y: number, m: number, d: number, h = 18) => new Date(y, m - 1, d, h, 30);
const claude: AgentInfo = { id: "claude", title: "Claude Code", available: true, detail: "2.1", bin: "/bin/claude" };

let root: string;
before(async () => {
  root = await mkdtemp(join(tmpdir(), "zv-reports-wl-"));
  for (const d of ["log", "sources/git", "sources/agent-sessions", "inbox/transcripts", "processed/claude-sessions", "summaries", "reports/daily"]) await mkdir(join(root, d), { recursive: true });
  await writeFile(join(root, "log", "2026-10.md"), "# 2026-10 로그\n\n- 10-20 [[zaevis]] #done 지난주 일\n- 10-26 [[zaevis]] #decision 리포트는 에이전트로 (src: 세션)\n- 10-27 [[zaevis]] #done 리포트 모듈 작성\n- 10-28 [[zaevis]] #blocked 미래의 줄\n");
  await writeFile(join(root, "sources", "git", "2026-10-27.md"), "# git · 2026-10-27\n\n## zaevis\n\n- 11:00 `abc1234` reports.ts 추가 — 박재\n");
  await writeFile(join(root, "sources", "git", "2026-10-26.md"), "# git · 2026-10-26\n\n- 09:00 `def5678` ask 리팩터 — 박재\n");
  await writeFile(join(root, "sources", "git", "2026-10-19.md"), "# git · 2026-10-19\n\n- 옛날 커밋\n");
  await writeFile(join(root, "sources", "agent-sessions", "2026-10-27.md"), "# 세션 · 2026-10-27\n\n## Claude Code · 10:00–11:00 리포트 설계\n\n긴 세션 " + "x".repeat(20_000) + "\n");
  await writeFile(join(root, "inbox", "transcripts", "2026-10-27_회의.txt"), "회의: 리포트 요일 설정은 주중 기본\n");
  await writeFile(join(root, "processed", "claude-sessions", "2026-10-26_zaevis.md"), "## 21:00 질문 모드\n- 결과: 대화 저장\n");
  await writeFile(join(root, "inbox", "transcripts", "2026-10-27_빈것.txt"), "   \n");
  await writeFile(join(root, "summaries", "2026-09.md"), "# 2026-09 작업 정리\n\n정리가 쓴 월간 초안\n");
  await writeFile(join(root, "reports", "daily", "2026-10-26.md"), "---\nkind: daily\nperiod: 2026-10-26\ncreatedAt: 2026-10-26T10:00:00.000Z\nagent: claude\n---\n# 2026-10-26 (월) 일간 리포트\n\n## 한 일\n- ask 리팩터 (근거: 2026-10-26 sources/git/2026-10-26.md)\n");
});

test("reports: ISO weeks and the periods a run defaults to", () => {
  assert.deepEqual(isoWeek(at(2026, 10, 27)), { year: 2026, week: 44 });
  assert.deepEqual(isoWeek(at(2025, 12, 29)), { year: 2026, week: 1 }, "Dec 29 2025 starts 2026-W01");
  assert.deepEqual(isoWeek(at(2027, 1, 3)), { year: 2026, week: 53 }, "2026 has 53 weeks");
  assert.equal(isoWeekStart(2026, 44).toDateString(), at(2026, 10, 26).toDateString());
  assert.equal(defaultPeriod("daily", at(2026, 10, 27, 18)), "2026-10-27");
  assert.equal(defaultPeriod("daily", at(2026, 10, 27, 9)), "2026-10-26", "a morning run reports yesterday");
  assert.equal(defaultPeriod("weekly", at(2026, 10, 26)), "2026-W43", "Monday → last week");
  assert.equal(defaultPeriod("weekly", at(2026, 11, 1)), "2026-W44", "Sunday → this week");
  assert.equal(defaultPeriod("monthly", at(2026, 1, 1)), "2025-12");
  assert.deepEqual(periodRange("weekly", "2026-W44"), { from: "2026-10-26", to: "2026-11-01", label: "2026-W44 (10-26 ~ 11-01)" });
  assert.deepEqual(periodRange("monthly", "2026-02"), { from: "2026-02-01", to: "2026-02-28", label: "2026-02" });
  assert.equal(periodRange("daily", "2026-10-27").label, "2026-10-27 (화)");
  assert.ok(isValidPeriod("daily", "2026-10-27") && isValidPeriod("weekly", "2026-W53") && isValidPeriod("monthly", "2026-12"));
  assert.ok(!isValidPeriod("daily", "2026-02-30") && !isValidPeriod("weekly", "2025-W53") && !isValidPeriod("monthly", "2026-13") && !isValidPeriod("daily", "../x"));
  assert.equal(reportPath("monthly", "2026-10"), "summaries/2026-10.md");
  assert.equal(reportPath("weekly", "2026-W44"), "reports/weekly/2026-W44.md");
});

test("reports: settings are normalised and patched with validation", () => {
  assert.deepEqual(normalizeReportsSetting(undefined), DEFAULT_REPORTS);
  const s = normalizeReportsSetting({ daily: { enabled: true, days: ["sat", "sat", "x"] }, weekly: { day: "fri" }, monthly: { enabled: false, day: 40 } });
  assert.deepEqual(s, { daily: { enabled: true, days: ["sat"] }, weekly: { enabled: false, day: "fri" }, monthly: { enabled: false, day: 1 } });
  const next = mergeReportsSetting(s, { daily: { days: ["sun", "mon"] }, monthly: { enabled: true, day: 15 } });
  assert.deepEqual(next.daily, { enabled: true, days: ["mon", "sun"] }, "canonical weekday order");
  assert.deepEqual(next.monthly, { enabled: true, day: 15 });
  assert.equal(next.weekly.day, "fri", "untouched parts stay");
  assert.throws(() => mergeReportsSetting(s, { daily: { days: ["funday"] } }), /mon…sun/);
  assert.throws(() => mergeReportsSetting(s, { weekly: { day: 3 } }), /weekly\.day/);
  assert.throws(() => mergeReportsSetting(s, { monthly: { day: 31 } }), /1~28/);
});

test("reports: what is due — weekday presets, the weekly day, the 1st of the month, and never twice", async () => {
  const setting: ReportsSetting = { daily: { enabled: true, days: ["mon", "tue", "wed", "thu", "fri"] }, weekly: { enabled: true, day: "mon" }, monthly: { enabled: true, day: 1 } };
  const tue = at(2026, 10, 27);
  assert.deepEqual(dueReports(setting, root, undefined, tue), [{ kind: "daily", period: "2026-10-27" }]);
  const sat = at(2026, 10, 31);
  assert.deepEqual(dueReports(setting, root, undefined, sat), [], "Saturday is not a weekday");
  assert.deepEqual(dueReports({ ...setting, daily: { enabled: true, days: ["sat", "sun"] } }, root, undefined, sat), [{ kind: "daily", period: "2026-10-31" }]);
  const monNov2 = at(2026, 11, 2);
  assert.deepEqual(dueReports(setting, root, undefined, monNov2), [{ kind: "daily", period: "2026-11-02" }, { kind: "weekly", period: "2026-W44" }]);
  const nov1 = at(2026, 11, 1); // a Sunday: no daily, monthly on the 1st
  assert.deepEqual(dueReports(setting, root, undefined, nov1), [{ kind: "monthly", period: "2026-10" }]);
  assert.deepEqual(dueReports({ ...setting, daily: { ...setting.daily, enabled: false }, weekly: { enabled: false, day: "mon" }, monthly: { enabled: false, day: 1 } }, root, undefined, monNov2), []);
  // a morning run on Tuesday makes Monday's report — unless that file already exists
  assert.deepEqual(dueReports(setting, root, undefined, at(2026, 10, 27, 8)), [], "reports/daily/2026-10-26.md exists");
  // the last run for the period (even failed) is not repeated
  assert.deepEqual(dueReports(setting, root, { lastRun: { daily: { kind: "daily", period: "2026-10-27", at: "", ok: false, agent: "claude", ms: 1, error: "x" } } }, tue), []);
});

test("reports: inputs are the period's log lines, the smaller reports, then raw files newest first within the cap", async () => {
  const day = await gatherReportInputs(root, "daily", periodRange("daily", "2026-10-27"));
  assert.equal(day.logLines, 1);
  assert.deepEqual(day.files, ["log/2026-10.md", "inbox/transcripts/2026-10-27_회의.txt", "sources/agent-sessions/2026-10-27.md", "sources/git/2026-10-27.md"], "no 10-26 files, no empty transcript, no reports for a daily");
  assert.match(day.text, /===== log\/2026-10\.md \(2026-10\) =====\n- 10-27 \[\[zaevis\]\] #done 리포트 모듈 작성/);
  assert.doesNotMatch(day.text, /10-26 \[\[zaevis\]\] #decision/);
  assert.match(day.text, /…\(잘림\)/, "a 20k session file is clipped per file");
  assert.equal(day.truncated, false);

  const week = await gatherReportInputs(root, "weekly", periodRange("weekly", "2026-W44"));
  assert.equal(week.logLines, 3, "10-26, 10-27, 10-28 — not 10-20");
  assert.equal(week.files[1], "reports/daily/2026-10-26.md", "the daily report of the week rides along, without its front matter");
  assert.doesNotMatch(week.text, /createdAt:/);
  assert.deepEqual(week.files.slice(2, 5), ["inbox/transcripts/2026-10-27_회의.txt", "sources/agent-sessions/2026-10-27.md", "sources/git/2026-10-27.md"], "newest day first");
  assert.ok(week.files.includes("processed/claude-sessions/2026-10-26_zaevis.md"));
  assert.ok(!week.files.includes("sources/git/2026-10-19.md"));

  const capped = await gatherReportInputs(root, "weekly", periodRange("weekly", "2026-W44"), 400);
  assert.equal(capped.truncated, true);
  assert.deepEqual(capped.files, ["log/2026-10.md", "reports/daily/2026-10-26.md", "inbox/transcripts/2026-10-27_회의.txt"], "log lines, reports and the newest small file fit; the rest did not");
  const p = buildReportPrompt("weekly", "2026-W44", capped);
  assert.match(p, /# 2026-W44 \(10-26 ~ 11-01\) 주간 리포트/);
  assert.match(p, /근거: YYYY-MM-DD 파일경로/);
  assert.match(p, /원본 일부 생략/);
  assert.match(buildReportPrompt("monthly", "2026-10", day), /# 2026-10 작업 정리/);
  assert.doesNotMatch(buildReportPrompt("daily", "2026-10-27", day), /한 줄 요약/);
});

test("reports: a run writes the file with front matter, records state and notifies; the list and read see it", async () => {
  const calls: Array<{ bin: string; args: string[]; cwd: string }> = [];
  const exec: Exec = async (bin, args, cwd) => {
    calls.push({ bin, args, cwd });
    return { ok: true, stdout: "```markdown\n# 2026-10-27 (화) 일간 리포트\n\n## 한 일\n- 리포트 모듈 작성 (근거: 2026-10-27 sources/git/2026-10-27.md)\n```", stderr: "" };
  };
  const notes: string[] = [];
  const runner = new ReportRunner({ exec, notify: (t, b) => notes.push(`${t}: ${b}`) });
  const cfg = { worklogDir: root, digest: { agent: "auto" as const, model: "", weekly: true, review: true } };
  const p = runner.run(cfg, claude, "daily", "2026-10-27");
  assert.deepEqual(runner.current && { kind: runner.current.kind, period: runner.current.period }, { kind: "daily", period: "2026-10-27" });
  assert.equal(runner.run(cfg, claude, "weekly", "2026-W44"), p, "a second call while running gets the same promise");
  const r = await p;
  assert.equal(r.ok, true);
  assert.equal(r.path, "reports/daily/2026-10-27.md");
  assert.equal(calls[0].cwd, root);
  assert.ok(calls[0].args.includes("--tools") && calls[0].args[calls[0].args.indexOf("--tools") + 1] === "", "read-only CLI invocation");
  assert.match(calls[0].args[1], /이 기록만 근거로 일간 리포트/);
  const md = await readFile(join(root, "reports", "daily", "2026-10-27.md"), "utf8");
  assert.match(md, /^---\nkind: daily\nperiod: 2026-10-27\nrange: 2026-10-27\.\.2026-10-27\ncreatedAt: \d{4}.*\nagent: claude\ninputs: 4\n---\n# 2026-10-27 \(화\) 일간 리포트\n/);
  assert.doesNotMatch(md, /```/, "the code fence is stripped");
  assert.equal(loadState().reports?.lastRun.daily?.period, "2026-10-27");
  assert.deepEqual(notes, ["일간 리포트 준비: 2026-10-27 (화) — 리포트 탭에서 보세요."]);
  assert.equal(runner.current, null);

  const list = await listReports(root);
  assert.deepEqual(list.daily.map((e) => e.period), ["2026-10-27", "2026-10-26"]);
  assert.equal(list.daily[0].agent, "claude");
  assert.deepEqual(list.monthly.map((e) => [e.period, e.agent]), [["2026-09", null]], "the digest's summary is listed without an agent");
  const read = await readReport(root, "daily", "2026-10-27");
  assert.equal(read?.markdown.startsWith("# 2026-10-27 (화) 일간 리포트"), true, "front matter stripped");
  assert.equal(read?.range.label, "2026-10-27 (화)");
  assert.equal(await readReport(root, "daily", "2026-10-25"), null);
});

test("reports: the digest's monthly summary reads too, and a failed run is recorded with its error", async () => {
  const m = await readReport(root, "monthly", "2026-09");
  assert.equal(m?.markdown, "# 2026-09 작업 정리\n\n정리가 쓴 월간 초안\n");
  const runner = new ReportRunner({ exec: async () => ({ ok: false, stdout: "", stderr: "Not logged in" }) });
  const cfg = { worklogDir: root, digest: { agent: "auto" as const, model: "", weekly: true, review: true } };
  const r = await runner.run(cfg, claude, "daily", "2026-10-26");
  assert.equal(r.ok, false);
  assert.match(r.error ?? "", /Not logged in/);
  assert.equal(loadState().reports?.lastRun.daily?.error, r.error);
  const empty = await runner.run(cfg, claude, "daily", "2026-10-01");
  assert.match(empty.error ?? "", /기록이 없습니다/);
  // a monthly report keeps the summaries/ place: the old summary endpoint hides its front matter
  await writeFile(join(root, "summaries", "2026-10.md"), "---\nkind: monthly\nperiod: 2026-10\ncreatedAt: 2026-11-01T09:00:00.000Z\nagent: claude\n---\n# 2026-10 작업 정리\n\n리포트\n");
  assert.equal(await new Worklog(root).summary("2026-10"), "# 2026-10 작업 정리\n\n리포트\n");
  assert.deepEqual((await listReports(root)).monthly.map((e) => [e.period, e.agent]), [["2026-10", "claude"], ["2026-09", null]]);
});

// ── HTTP ───────────────────────────────────────────────────────────────────────

const fakeSearch: SearchBackend = {
  async status() {
    return {};
  },
  async refresh() {
    return {};
  },
  async search(query) {
    return { ok: true, query, hits: [] };
  },
  async close() {},
};

let server: Server;
let base: string;
let setting: ReportsSetting = normalizeReportsSetting(undefined);
let running = false;
const runs: Array<[string, string | undefined]> = [];

before(async () => {
  server = createApp({
    worklog: new Worklog(root),
    search: fakeSearch,
    reports: {
      status: async () => ({ setting, running: running ? { kind: "daily", period: "2026-10-27" } : null, lastRun: {}, reports: await listReports(root), defaults: { daily: "2026-10-27", weekly: "2026-W43", monthly: "2026-09" } }),
      read: (kind, period) => (kind === "daily" || kind === "weekly" || kind === "monthly" ? readReport(root, kind, period) : Promise.resolve(null)),
      update: async (patch) => {
        setting = mergeReportsSetting(setting, patch);
        return { setting };
      },
      run: async (kind, period) => {
        runs.push([kind, period]);
        if (kind === "x") return { started: false, status: 400, error: "bad_kind", reason: "종류" };
        if (running) return { started: false, status: 409, error: "busy", reason: "실행 중" };
        running = true;
        return { started: true, kind, period: period ?? "2026-10-27", agent: "claude" };
      },
    },
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(() => server.close());

const call = async (method: string, path: string, body?: unknown) => {
  const r = await fetch(base + path, { method, headers: { "content-type": "application/json", "x-zaevis": "1" }, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: r.status, body: (await r.json()) as Record<string, any> };
};

test("reports API: status, one report, settings, run (202 / 409 / 400 / 404)", async () => {
  const st = await call("GET", "/api/reports");
  assert.equal(st.status, 200);
  assert.equal(st.body.setting.monthly.enabled, true);
  assert.deepEqual(st.body.reports.daily.map((e: { period: string }) => e.period), ["2026-10-27", "2026-10-26"]);
  assert.equal(st.body.defaults.weekly, "2026-W43");

  const one = await call("GET", "/api/reports/daily/2026-10-27");
  assert.equal(one.status, 200);
  assert.equal(one.body.path, "reports/daily/2026-10-27.md");
  assert.match(one.body.markdown, /^# 2026-10-27/);
  assert.equal((await call("GET", "/api/reports/daily/2026-01-01")).status, 404);
  assert.equal((await call("GET", "/api/reports/daily/..%2F..%2Fetc")).status, 404);
  assert.equal((await call("GET", "/api/reports/yearly/2026")).status, 404);
  assert.equal((await call("GET", "/api/reports/daily")).status, 404);

  const put = await call("PUT", "/api/reports/settings", { daily: { enabled: true, days: ["sat", "sun"] }, weekly: { day: "fri" } });
  assert.equal(put.status, 200);
  assert.deepEqual(put.body.setting.daily, { enabled: true, days: ["sat", "sun"] });
  assert.equal(put.body.setting.weekly.day, "fri");
  const bad = await call("PUT", "/api/reports/settings", { monthly: { day: 0 } });
  assert.equal(bad.status, 400);
  assert.match(bad.body.message, /1~28/);
  assert.equal((await call("PUT", "/api/reports/other", {})).status, 404);

  const run = await call("POST", "/api/reports/run", { kind: "daily" });
  assert.equal(run.status, 202);
  assert.deepEqual(run.body, { started: true, kind: "daily", period: "2026-10-27", agent: "claude" });
  const busy = await call("POST", "/api/reports/run", { kind: "weekly", period: "2026-W44" });
  assert.equal(busy.status, 409);
  assert.equal(busy.body.error, "busy");
  assert.deepEqual(runs, [["daily", undefined], ["weekly", "2026-W44"]]);
  assert.equal((await call("POST", "/api/reports/run", { kind: "x" })).status, 400);
  assert.equal((await call("POST", "/api/reports/other", {})).status, 404);
  assert.equal((await call("GET", "/api/reports")).body.running.kind, "daily");
});
