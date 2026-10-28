// "리포트" (reports): a daily / weekly / monthly write-up of what the worklog recorded for that period —
// what was done, decided, blocked, and what comes next — each item with the date/file it rests on.
// The inputs are gathered here (log lines, sources/*/<date>.md, inbox and processed transcripts and
// session notes, and the smaller reports a bigger one can build on); the text is written by the same
// agents the question mode uses (ask.ts `generateWithFallback`: an installed CLI run without tools, or the
// OpenRouter key, hopping to the next only on a quota error when the digest setting is auto).
//
//   setting  config.json → reports: { daily: { enabled, days[] }, weekly: { enabled, day }, monthly: { enabled, day } }
//   state    state.json  → reports: { lastRun: { daily?, weekly?, monthly? } }
//   files    reports/daily/YYYY-MM-DD.md · reports/weekly/YYYY-Www.md · summaries/YYYY-MM.md (the monthly summary's place)
//   log      $ZAEVIS_HOME/reports.log

import { existsSync, mkdirSync } from "node:fs";
import { appendFile, mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import { join, posix } from "node:path";
import { generateWithFallback, type GenerateOpts } from "./ask.ts";
import { fallbackCandidates, plannedRail, type RailStop } from "./rail.ts";
import { loadState, saveState, stateDir, type AppConfig } from "./config.ts";
import { DEFAULT_OPENROUTER_MODEL, type AgentId, type AgentInfo } from "./digest.ts";
import { parseFrontMatter, parseLog } from "./worklog.ts";

export type ReportKind = "daily" | "weekly" | "monthly";
export const KINDS: readonly ReportKind[] = ["daily", "weekly", "monthly"];
export const KIND_LABEL: Record<ReportKind, string> = { daily: "일간", weekly: "주간", monthly: "월간" };

export type Weekday = "mon" | "tue" | "wed" | "thu" | "fri" | "sat" | "sun";
export const WEEKDAYS: readonly Weekday[] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
export const WEEKDAY_LABEL: Record<Weekday, string> = { mon: "월", tue: "화", wed: "수", thu: "목", fri: "금", sat: "토", sun: "일" };
export const WEEKDAY_PRESETS: Record<"weekdays" | "weekend" | "everyday", Weekday[]> = {
  weekdays: ["mon", "tue", "wed", "thu", "fri"],
  weekend: ["sat", "sun"],
  everyday: [...WEEKDAYS],
};

export type ReportsSetting = {
  /** A daily report for each day whose weekday is in `days` (the day reported, not the day the job runs). */
  daily: { enabled: boolean; days: Weekday[] };
  /** The weekly report is written on `day`; it covers the ISO week (Mon–Sun) that contains the day before. */
  weekly: { enabled: boolean; day: Weekday };
  /** The monthly report is written on day `day` (1–28) and covers the previous month. */
  monthly: { enabled: boolean; day: number };
};

export const DEFAULT_REPORTS: ReportsSetting = {
  daily: { enabled: false, days: [...WEEKDAY_PRESETS.weekdays] },
  weekly: { enabled: false, day: "mon" },
  monthly: { enabled: true, day: 1 },
};

export type ReportRun = { kind: ReportKind; period: string; at: string; ok: boolean; agent: AgentId; ms: number; path?: string; error?: string; rail?: RailStop[] };
export type ReportsState = { lastRun: Partial<Record<ReportKind, ReportRun>> };
export type ReportEntry = { kind: ReportKind; period: string; path: string; createdAt: string; agent: string | null };
export type Report = ReportEntry & { range: { from: string; to: string; label: string }; markdown: string };
export type ReportsStatus = {
  setting: ReportsSetting;
  running: { kind: ReportKind; period: string; startedAt: string; agent: AgentId; rail?: RailStop[] } | null;
  lastRun: Partial<Record<ReportKind, ReportRun>>;
  reports: Record<ReportKind, ReportEntry[]>;
  /** What `POST /api/reports/run` without a period would make right now. */
  defaults: Record<ReportKind, string>;
};

/** A report run gets longer than a question: a month of inputs can take a while to read. */
const RUN_TIMEOUT_MS = 10 * 60_000;
const CAP_CHARS = 120_000;
const FILE_CHARS = 12_000;

// ── settings ───────────────────────────────────────────────────────────────────

const isWeekday = (v: unknown): v is Weekday => typeof v === "string" && (WEEKDAYS as readonly string[]).includes(v);

/** Fills a (possibly partial or malformed) config value with the defaults; never throws. */
export function normalizeReportsSetting(raw: unknown): ReportsSetting {
  const r = (raw && typeof raw === "object" ? raw : {}) as Record<string, any>;
  const days = Array.isArray(r.daily?.days) ? [...new Set(r.daily.days.filter(isWeekday))] : null;
  return {
    daily: { enabled: r.daily?.enabled === true, days: days ?? [...DEFAULT_REPORTS.daily.days] },
    weekly: { enabled: r.weekly?.enabled === true, day: isWeekday(r.weekly?.day) ? r.weekly.day : DEFAULT_REPORTS.weekly.day },
    monthly: { enabled: r.monthly?.enabled !== false, day: Number.isInteger(r.monthly?.day) && r.monthly.day >= 1 && r.monthly.day <= 28 ? r.monthly.day : DEFAULT_REPORTS.monthly.day },
  };
}

/** Applies a settings patch from the API; throws (→ 400) on a value that is not a weekday / day of month. */
export function mergeReportsSetting(cur: ReportsSetting, patch: Record<string, unknown>): ReportsSetting {
  const next: ReportsSetting = { daily: { ...cur.daily, days: [...cur.daily.days] }, weekly: { ...cur.weekly }, monthly: { ...cur.monthly } };
  const d = patch.daily as Record<string, unknown> | undefined;
  if (d && typeof d === "object") {
    if (typeof d.enabled === "boolean") next.daily.enabled = d.enabled;
    if (d.days !== undefined) {
      if (!Array.isArray(d.days) || !d.days.every(isWeekday)) throw new Error("daily.days 는 mon…sun 중에서 골라야 합니다.");
      next.daily.days = WEEKDAYS.filter((w) => (d.days as Weekday[]).includes(w)); // canonical order, no duplicates
    }
  }
  const w = patch.weekly as Record<string, unknown> | undefined;
  if (w && typeof w === "object") {
    if (typeof w.enabled === "boolean") next.weekly.enabled = w.enabled;
    if (w.day !== undefined) {
      if (!isWeekday(w.day)) throw new Error("weekly.day 는 mon…sun 중 하나여야 합니다.");
      next.weekly.day = w.day;
    }
  }
  const m = patch.monthly as Record<string, unknown> | undefined;
  if (m && typeof m === "object") {
    if (typeof m.enabled === "boolean") next.monthly.enabled = m.enabled;
    if (m.day !== undefined) {
      if (!Number.isInteger(m.day) || (m.day as number) < 1 || (m.day as number) > 28) throw new Error("monthly.day 는 1~28 사이여야 합니다.");
      next.monthly.day = m.day as number;
    }
  }
  return next;
}

// ── periods ────────────────────────────────────────────────────────────────────

const pad = (n: number) => String(n).padStart(2, "0");
export const ymd = (d: Date): string => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
/** Noon local time: adding days never crosses a DST change into the wrong date. */
const atNoon = (y: number, m: number, d: number) => new Date(y, m - 1, d, 12);
const parseYmd = (s: string): Date => atNoon(Number(s.slice(0, 4)), Number(s.slice(5, 7)), Number(s.slice(8, 10)));
const addDays = (d: Date, n: number): Date => {
  const x = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 12);
  x.setDate(x.getDate() + n);
  return x;
};
export const weekdayOf = (d: Date): Weekday => WEEKDAYS[(d.getDay() + 6) % 7];

export function isoWeek(d: Date): { year: number; week: number } {
  const t = addDays(d, 3 - ((d.getDay() + 6) % 7)); // the Thursday of d's week decides the year
  const year = t.getFullYear();
  const jan4 = atNoon(year, 1, 4);
  const week = 1 + Math.round(((t.getTime() - jan4.getTime()) / 86_400_000 - 3 + ((jan4.getDay() + 6) % 7)) / 7);
  return { year, week };
}

/** Monday of ISO week `week` of `year`. */
export function isoWeekStart(year: number, week: number): Date {
  const jan4 = atNoon(year, 1, 4);
  return addDays(jan4, -((jan4.getDay() + 6) % 7) + (week - 1) * 7);
}

const PERIOD_RE: Record<ReportKind, RegExp> = { daily: /^\d{4}-\d{2}-\d{2}$/, weekly: /^\d{4}-W\d{2}$/, monthly: /^\d{4}-\d{2}$/ };

export const isKind = (v: unknown): v is ReportKind => typeof v === "string" && (KINDS as readonly string[]).includes(v);

export function isValidPeriod(kind: ReportKind, period: string): boolean {
  if (!PERIOD_RE[kind].test(period)) return false;
  if (kind === "daily") return ymd(parseYmd(period)) === period;
  if (kind === "weekly") {
    const week = Number(period.slice(6));
    return week >= 1 && week <= 53 && isoWeek(isoWeekStart(Number(period.slice(0, 4)), week)).week === week;
  }
  const m = Number(period.slice(5, 7));
  return m >= 1 && m <= 12;
}

/** The report a scheduled run (or `run` without a period) makes right now. */
export function defaultPeriod(kind: ReportKind, now = new Date()): string {
  // Before noon the day's work is not yet done: the morning run (a Mac that slept through 18:30) reports yesterday.
  const day = now.getHours() < 12 ? addDays(now, -1) : now;
  if (kind === "daily") return ymd(day);
  if (kind === "weekly") {
    const w = isoWeek(addDays(now, -1)); // on Monday that is last week; on Sunday this week
    return `${w.year}-W${pad(w.week)}`;
  }
  const prev = new Date(now.getFullYear(), now.getMonth() - 1, 1, 12);
  return `${prev.getFullYear()}-${pad(prev.getMonth() + 1)}`;
}

/** First and last day (inclusive) a period covers, and how the title names it. */
export function periodRange(kind: ReportKind, period: string): { from: string; to: string; label: string } {
  if (kind === "daily") {
    const d = parseYmd(period);
    return { from: period, to: period, label: `${period} (${WEEKDAY_LABEL[weekdayOf(d)]})` };
  }
  if (kind === "weekly") {
    const start = isoWeekStart(Number(period.slice(0, 4)), Number(period.slice(6)));
    const end = addDays(start, 6);
    return { from: ymd(start), to: ymd(end), label: `${period} (${ymd(start).slice(5)} ~ ${ymd(end).slice(5)})` };
  }
  const y = Number(period.slice(0, 4));
  const m = Number(period.slice(5, 7));
  return { from: `${period}-01`, to: ymd(atNoon(y, m + 1, 0)), label: period };
}

/** Where the report lives, relative to the worklog. The monthly one keeps the summaries/ place the digest used. */
export function reportPath(kind: ReportKind, period: string): string {
  return kind === "monthly" ? posix.join("summaries", `${period}.md`) : posix.join("reports", kind, `${period}.md`);
}

export function reportTitle(kind: ReportKind, period: string): string {
  const r = periodRange(kind, period);
  return kind === "monthly" ? `${period} 작업 정리` : `${r.label} ${KIND_LABEL[kind]} 리포트`;
}

// ── due ────────────────────────────────────────────────────────────────────────

/**
 * Reports the daily job should make now, in order. A period is made once: never when its file
 * exists or when the last run (even a failed one) was for it — a failure is not retried every day.
 */
export function dueReports(setting: ReportsSetting, worklogDir: string, state: ReportsState | undefined, now = new Date()): Array<{ kind: ReportKind; period: string }> {
  const out: Array<{ kind: ReportKind; period: string }> = [];
  const fresh = (kind: ReportKind, period: string) => !existsSync(join(worklogDir, reportPath(kind, period))) && state?.lastRun?.[kind]?.period !== period;
  if (setting.daily.enabled) {
    const period = defaultPeriod("daily", now);
    if (setting.daily.days.includes(weekdayOf(parseYmd(period))) && fresh("daily", period)) out.push({ kind: "daily", period });
  }
  if (setting.weekly.enabled && weekdayOf(now) === setting.weekly.day) {
    const period = defaultPeriod("weekly", now);
    if (fresh("weekly", period)) out.push({ kind: "weekly", period });
  }
  if (setting.monthly.enabled && now.getDate() === setting.monthly.day) {
    const period = defaultPeriod("monthly", now);
    if (fresh("monthly", period)) out.push({ kind: "monthly", period });
  }
  return out;
}

// ── inputs ─────────────────────────────────────────────────────────────────────

export type ReportInputs = { files: string[]; text: string; logLines: number; truncated: boolean };

async function listDir(dir: string): Promise<string[]> {
  try {
    return (await readdir(dir)).filter((n) => !n.startsWith(".")).sort();
  } catch {
    return [];
  }
}

function datesBetween(from: string, to: string): string[] {
  const out: string[] = [];
  for (let d = parseYmd(from); ymd(d) <= to; d = addDays(d, 1)) out.push(ymd(d));
  return out;
}

/**
 * Everything the report rests on, as labelled blocks. Log lines and the smaller reports of the
 * period come first (short, already condensed); then the raw files newest first until the cap.
 */
export async function gatherReportInputs(worklogDir: string, kind: ReportKind, range: { from: string; to: string }, capChars = CAP_CHARS): Promise<ReportInputs> {
  const blocks: Array<{ rel: string; body: string; date: string }> = [];
  const dates = datesBetween(range.from, range.to);
  const dateSet = new Set(dates);
  let logLines = 0;

  // 1. log/YYYY-MM.md — only the lines dated inside the range
  const months = [...new Set(dates.map((d) => d.slice(0, 7)))];
  for (const month of months) {
    const rel = posix.join("log", `${month}.md`);
    const md = await readFile(join(worklogDir, rel), "utf8").catch(() => null);
    if (md === null) continue;
    const lines = parseLog(md).filter((e) => {
      const [mm, dd] = e.date.split("-").map(Number);
      return dateSet.has(`${month.slice(0, 4)}-${pad(mm)}-${pad(dd)}`);
    });
    if (!lines.length) continue;
    logLines += lines.length;
    blocks.push({ rel, date: month, body: lines.map((e) => e.raw).join("\n") });
  }

  // 2. smaller reports inside the period (weekly ← daily, monthly ← weekly + daily)
  const smaller: Array<[ReportKind, string]> = [];
  if (kind === "monthly") {
    const weeks = new Map<string, Date>();
    for (const d of dates) {
      const w = isoWeek(parseYmd(d));
      weeks.set(`${w.year}-W${pad(w.week)}`, parseYmd(d));
    }
    for (const w of weeks.keys()) smaller.push(["weekly", w]);
  }
  if (kind !== "daily") for (const d of dates) smaller.push(["daily", d]);
  for (const [k, p] of smaller) {
    const rel = reportPath(k, p);
    const md = await readFile(join(worklogDir, rel), "utf8").catch(() => null);
    if (md !== null) blocks.push({ rel, date: p, body: parseFrontMatter(md).body });
  }

  // 3. raw collections and inbox files, newest first
  const raw: Array<{ rel: string; date: string }> = [];
  for (const src of await listDir(join(worklogDir, "sources"))) {
    for (const name of await listDir(join(worklogDir, "sources", src))) {
      const day = /^(\d{4}-\d{2}-\d{2})\.md$/.exec(name)?.[1];
      if (day && dateSet.has(day)) raw.push({ rel: posix.join("sources", src, name), date: day });
    }
  }
  for (const box of ["inbox", "processed"]) {
    for (const sub of ["transcripts", "claude-sessions"]) {
      for (const name of await listDir(join(worklogDir, box, sub))) {
        const day = /^(\d{4}-\d{2}-\d{2})/.exec(name)?.[1];
        if (day && dateSet.has(day) && /\.(md|txt)$/.test(name)) raw.push({ rel: posix.join(box, sub, name), date: day });
      }
    }
  }
  raw.sort((a, b) => (a.date === b.date ? a.rel.localeCompare(b.rel) : a.date < b.date ? 1 : -1));
  let truncated = false;
  let text = "";
  const files: string[] = [];
  const add = (rel: string, date: string, body: string): boolean => {
    if (body.length > FILE_CHARS) body = body.slice(0, FILE_CHARS) + "\n…(잘림)";
    const chunk = `\n\n===== ${rel} (${date}) =====\n${body.trim()}`;
    if (text.length + chunk.length > capChars) return false;
    text += chunk;
    files.push(rel);
    return true;
  };
  for (const b of blocks) if (!add(b.rel, b.date, b.body)) truncated = true;
  for (const r of raw) {
    if (truncated) break;
    const body = await readFile(join(worklogDir, r.rel), "utf8").catch(() => null);
    if (body === null || !body.trim()) continue;
    if (!(await stat(join(worklogDir, r.rel))).isFile()) continue;
    if (!add(r.rel, r.date, body)) truncated = true;
  }
  return { files, text: text.trim(), logLines, truncated };
}

// ── prompt ─────────────────────────────────────────────────────────────────────

export function buildReportPrompt(kind: ReportKind, period: string, inputs: Pick<ReportInputs, "text" | "truncated">): string {
  const r = periodRange(kind, period);
  const span = kind === "daily" ? `${r.from} 하루` : `${r.from} ~ ${r.to}`;
  const grouping = kind === "daily" ? "" : "\n- 한 일은 프로젝트(저장소)별로 묶어 소제목 없이 항목 앞에 **프로젝트명**을 붙인다. 맨 앞에 \"## 한 줄 요약\" 절을 둔다(2~3문장).";
  return `아래는 내 작업 기록(worklog)에서 ${span}에 해당하는 원본이다. 이 기록만 근거로 ${KIND_LABEL[kind]} 리포트를 한국어로 쓴다.

규칙:
- 첫 줄은 "# ${reportTitle(kind, period)}". 그 다음 "## 한 일", "## 결정", "## 막힌 것", "## 다음 할 일" 네 절을 이 순서로 둔다. 각 절은 "- " 목록이고, 해당 내용이 없으면 "- 없음" 한 줄.${grouping}
- 각 항목 끝에 근거를 "(근거: YYYY-MM-DD 파일경로)" 꼴로 단다. 파일경로는 원본 블록 머리의 "===== 경로 (날짜) =====" 에 있는 경로를 그대로 쓴다. 근거가 여럿이면 "; "로 잇는다.
- 원본을 그대로 옮기지 않는다. 같은 일은 한 항목으로 묶고, 무엇을 왜 했는지가 보이게 한두 문장으로 쓴다. 셸 명령 이력은 다른 기록의 맥락 보충에만 쓴다.
- 기록에 없는 내용은 쓰지 않는다. 기록이 거의 없으면 그대로 "- 없음"으로 두고 지어내지 않는다.
- 파일을 열거나 명령을 실행하지 않는다. 서론·인사·마무리 말 없이 리포트 본문(마크다운)만 쓴다.${inputs.truncated ? "\n- 원본은 분량 상한에 맞춰 오래된 것부터 잘렸다. 빠진 날이 있으면 \"## 다음 할 일\" 끝에 \"- (원본 일부 생략)\"을 덧붙인다." : ""}

원본:
${inputs.text}`;
}

// ── files ──────────────────────────────────────────────────────────────────────

function frontMatter(meta: Record<string, string | number>): string {
  return `---\n${Object.entries(meta).map(([k, v]) => `${k}: ${v}`).join("\n")}\n---\n`;
}

async function entryOf(worklogDir: string, kind: ReportKind, period: string): Promise<(ReportEntry & { body: string; range: Report["range"] }) | null> {
  const path = reportPath(kind, period);
  const file = join(worklogDir, path);
  const md = await readFile(file, "utf8").catch(() => null);
  if (md === null) return null;
  const { meta, body } = parseFrontMatter(md);
  const createdAt = typeof meta.createdAt === "string" && meta.createdAt ? meta.createdAt : (await stat(file)).mtime.toISOString();
  const agent = typeof meta.agent === "string" && meta.agent ? meta.agent : null;
  return { kind, period, path, createdAt, agent, body, range: periodRange(kind, period) };
}

export async function readReport(worklogDir: string, kind: ReportKind, period: string): Promise<Report | null> {
  if (!isValidPeriod(kind, period)) return null;
  const e = await entryOf(worklogDir, kind, period);
  return e ? { kind: e.kind, period: e.period, path: e.path, createdAt: e.createdAt, agent: e.agent, range: e.range, markdown: e.body } : null;
}

/** Every report on disk, newest period first. Monthly summaries the digest wrote (no front matter) are listed too. */
export async function listReports(worklogDir: string): Promise<Record<ReportKind, ReportEntry[]>> {
  const out: Record<ReportKind, ReportEntry[]> = { daily: [], weekly: [], monthly: [] };
  for (const kind of KINDS) {
    const dir = join(worklogDir, kind === "monthly" ? "summaries" : join("reports", kind));
    const periods = (await listDir(dir))
      .filter((n) => n.endsWith(".md") && !n.startsWith("_"))
      .map((n) => n.slice(0, -3))
      .filter((p) => isValidPeriod(kind, p))
      .sort()
      .reverse();
    for (const p of periods) {
      const e = await entryOf(worklogDir, kind, p);
      if (e) out[kind].push({ kind, period: p, path: e.path, createdAt: e.createdAt, agent: e.agent });
    }
  }
  return out;
}

// ── runner ─────────────────────────────────────────────────────────────────────

export type ReportRunnerOpts = GenerateOpts & { notify?: (title: string, body: string) => void; log?: (line: string) => void };

/** One report at a time; shared by the server (API) and the daily job. */
export class ReportRunner {
  private running: { kind: ReportKind; period: string; startedAt: string; agent: AgentId; promise: Promise<ReportRun> } | null = null;
  private rail: RailStop[] = [];
  private readonly opts: ReportRunnerOpts;

  constructor(opts: ReportRunnerOpts = {}) {
    this.opts = opts;
  }

  get current(): { kind: ReportKind; period: string; startedAt: string; agent: AgentId; rail: RailStop[] } | null {
    return this.running ? { kind: this.running.kind, period: this.running.period, startedAt: this.running.startedAt, agent: this.running.agent, rail: this.rail } : null;
  }

  async status(cfg: Pick<AppConfig, "worklogDir" | "reports">, now = new Date()): Promise<ReportsStatus> {
    return {
      setting: cfg.reports,
      running: this.current,
      lastRun: loadState().reports?.lastRun ?? {},
      reports: await listReports(cfg.worklogDir),
      defaults: { daily: defaultPeriod("daily", now), weekly: defaultPeriod("weekly", now), monthly: defaultPeriod("monthly", now) },
    };
  }

  /**
   * Writes the report for `period` (overwriting an older one), records the outcome in state.json
   * and notifies. While a run is in progress the same promise is returned to a second caller.
   */
  run(cfg: Pick<AppConfig, "worklogDir" | "digest">, agent: AgentInfo, kind: ReportKind, period: string, chain?: AgentInfo[]): Promise<ReportRun> {
    if (this.running) return this.running.promise;
    if (!isValidPeriod(kind, period)) return Promise.reject(new Error(`기간 형식이 올바르지 않습니다: ${period}`));
    const startedAt = new Date().toISOString();
    const started = Date.now();
    const logFile = join(stateDir(), "reports.log");
    mkdirSync(stateDir(), { recursive: true });
    const log = (line: string) => {
      this.opts.log?.(line);
      void appendFile(logFile, `[${new Date().toLocaleString("sv-SE")}] ${line}\n`).catch(() => {});
    };
    const title = `${KIND_LABEL[kind]} 리포트 ${period}`;
    const promise = (async (): Promise<ReportRun> => {
      let run: ReportRun;
      try {
        const range = periodRange(kind, period);
        const inputs = await gatherReportInputs(cfg.worklogDir, kind, range);
        if (!inputs.files.length) throw new Error(`${range.label} 에 해당하는 기록이 없습니다.`);
        const candidates = chain && cfg.digest.agent === "auto" ? fallbackCandidates(cfg.digest, chain) : [];
        const list = candidates.length ? candidates : [agent];
        this.rail = chain ? plannedRail(cfg.digest, chain) : plannedRail({ agent: agent.id }, [agent]);
        if (this.running) this.running.agent = list[0].id;
        log(`${title} 시작 (${list.map((a) => a.title).join(" → ")}, 입력 ${inputs.files.length}개 파일 ${inputs.text.length}자, 로그 ${inputs.logLines}줄${inputs.truncated ? ", 잘림" : ""})`);
        const produced = await generateWithFallback(list, buildReportPrompt(kind, period, inputs), cfg.digest.model || DEFAULT_OPENROUTER_MODEL, cfg.worklogDir, {
          ...this.opts,
          timeoutMs: this.opts.timeoutMs ?? RUN_TIMEOUT_MS,
          planned: this.rail,
          onTrail: (stops) => {
            this.rail = stops;
            const cur = stops.find((s) => s.state === "running" || s.state === "wrote");
            if (cur && this.running) this.running.agent = cur.id;
          },
        });
        let body = produced.text.replace(/^```(?:markdown|md)?\s*\n([\s\S]*?)\n```\s*$/, "$1").trim(); // a fenced answer
        if (!body.startsWith("#")) body = `# ${reportTitle(kind, period)}\n\n${body}`;
        const path = reportPath(kind, period);
        const createdAt = new Date().toISOString();
        const file = join(cfg.worklogDir, path);
        await mkdir(join(file, ".."), { recursive: true });
        await writeFile(file, frontMatter({ kind, period, range: `${range.from}..${range.to}`, createdAt, agent: produced.agent.id, inputs: inputs.files.length }) + body + "\n");
        run = { kind, period, at: createdAt, ok: true, agent: produced.agent.id, ms: Date.now() - started, path, rail: produced.rail };
        log(`${title} 완료 (${run.ms}ms, ${produced.agent.title}) → ${path}`);
        const skipped = produced.rail.filter((s) => s.state === "quota").map((s) => s.title);
        this.opts.notify?.(`${KIND_LABEL[kind]} 리포트 준비`, `${skipped.length ? `${skipped.join(", ")} 할당량 → ${produced.agent.title}. ` : ""}${range.label} — 리포트 탭에서 보세요.`);
      } catch (err) {
        const failed = err as Error & { rail?: RailStop[] };
        run = { kind, period, at: new Date().toISOString(), ok: false, agent: this.running?.agent ?? agent.id, ms: Date.now() - started, error: failed.message, ...(failed.rail ? { rail: failed.rail } : this.rail.length ? { rail: this.rail } : {}) };
        log(`${title} 실패: ${run.error}`);
        this.opts.notify?.(`${KIND_LABEL[kind]} 리포트 실패`, run.error ?? "");
      }
      const state = loadState();
      state.reports = { lastRun: { ...(state.reports?.lastRun ?? {}), [kind]: run } };
      saveState(state);
      return run;
    })().finally(() => {
      this.running = null;
      this.rail = [];
    });
    this.running = { kind, period, startedAt, agent: agent.id, promise };
    return promise;
  }
}
