// Registry + collector. `collect()` runs the enabled sources and writes
// worklog/sources/<name>/<YYYY-MM-DD>.md, recording per-source status in ~/.zaevis/state.json.

import { existsSync } from "node:fs";
import { appendFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { loadSources, loadState, saveState, type AppConfig, type SourceSettings } from "../config.ts";
import { agentsSource } from "./agents.ts";
import { commandSource, SAFE_NAME } from "./command.ts";
import { gitSource } from "./git.ts";
import { shellHistorySource } from "./shellHistory.ts";
import { transcriptsSource } from "./transcripts.ts";
import { startOfDay, type Source } from "./types.ts";

// "agent-sessions" replaced the "claude-code" card (2026-10-27); day files it wrote stay under
// worklog/sources/claude-code/ and remain searchable.
export const BUILTIN: Source[] = [gitSource, agentsSource, shellHistorySource, transcriptsSource];

export type SourceInfo = {
  name: string;
  title: string;
  description: string;
  builtin: boolean;
  enabled: boolean;
  settings: Record<string, unknown>;
  options: Source["options"];
  lastRun: string | null;
  lastOk: boolean | null;
  lastError: string | null;
  lastNote: string | null;
};

function resolveSources(cfg: AppConfig): Array<{ source: Source; settings: SourceSettings; builtin: boolean }> {
  const conf = loadSources(cfg);
  const list = BUILTIN.map((source) => ({ source, settings: conf[source.name] ?? { enabled: true }, builtin: true }));
  for (const c of conf.custom ?? []) {
    if (!SAFE_NAME.test(c.name) || BUILTIN.some((b) => b.name === c.name)) continue;
    list.push({ source: commandSource(c.name, c.command, c.description), settings: { enabled: c.enabled !== false, command: c.command }, builtin: false });
  }
  return list;
}

export function listSources(cfg: AppConfig): SourceInfo[] {
  const state = loadState();
  return resolveSources(cfg).map(({ source, settings, builtin }) => {
    const st = state.sources[source.name] ?? {};
    const { enabled, ...rest } = settings;
    return {
      name: source.name,
      title: source.title,
      description: source.description,
      builtin,
      enabled: enabled !== false,
      settings: rest,
      options: source.options,
      lastRun: st.lastRun ?? null,
      lastOk: st.lastOk ?? null,
      lastError: st.lastError ?? null,
      lastNote: st.lastNote ?? null,
    };
  });
}

export type CollectStep = {
  name: string;
  title: string;
  state: "waiting" | "running" | "done" | "failed";
  line?: string;
  note?: string;
  error?: string;
  /** When this step started running. */
  since?: string;
};

/** What the collect screen draws while a run is in progress. `beat` moves even when a step is quiet; `outputAt` moves only when a source prints something. */
export type CollectProgress = {
  startedAt: string;
  beat: string;
  outputAt: string;
  current: { name: string; title: string; line: string } | null;
  steps: CollectStep[];
};

export type CollectOptions = { only?: string[]; backfillDays?: number; now?: Date; log?: (m: string) => void; onProgress?: (p: CollectProgress) => void };
export type CollectReport = Array<{ name: string; ok: boolean; days: string[]; note?: string; error?: string }>;

const header = (name: string, day: string) => `# ${name} · ${day}\n\n<!-- zaevis가 자동으로 만든 파일입니다. 직접 고치면 다음 수집 때 덮어씁니다. -->\n\n`;

async function writeDay(dir: string, name: string, day: string, body: string, append: boolean): Promise<void> {
  const file = join(dir, `${day}.md`);
  if (append && existsSync(file)) {
    const existing = await readFile(file, "utf8");
    const fresh = body.split("\n").filter((l) => l.trim() && !existing.includes(l));
    if (fresh.length) await appendFile(file, (existing.endsWith("\n") ? "" : "\n") + fresh.join("\n") + "\n");
    return;
  }
  await writeFile(file, header(name, day) + body.trim() + "\n");
}

export async function collect(cfg: AppConfig, opts: CollectOptions = {}): Promise<CollectReport> {
  const now = opts.now ?? new Date();
  const log = opts.log ?? ((m: string) => console.error(m));
  const state = loadState();
  const report: CollectReport = [];
  const targets = resolveSources(cfg).filter(({ source, settings }) => (opts.only?.length ? opts.only.includes(source.name) : settings.enabled !== false));
  const stamp = () => new Date().toISOString();
  const progress: CollectProgress = {
    startedAt: now.toISOString(),
    beat: now.toISOString(),
    outputAt: now.toISOString(),
    current: null,
    steps: targets.map(({ source }) => ({ name: source.name, title: source.title, state: "waiting" as const })),
  };
  const publish = () => opts.onProgress?.({ ...progress, current: progress.current ? { ...progress.current } : null, steps: progress.steps.map((s) => ({ ...s })) });
  const beat = () => {
    progress.beat = stamp();
    publish();
  };
  const note = (line: string) => {
    progress.beat = progress.outputAt = stamp();
    if (progress.current) progress.current.line = line;
    const step = progress.steps.find((s) => s.name === progress.current?.name);
    if (step) step.line = line;
    log(line);
    publish();
  };
  publish();

  for (const { source, settings } of targets) {
    const step = progress.steps.find((s) => s.name === source.name)!;
    const st = (state.sources[source.name] ??= {});
    // Re-read from the start of the last run's day so every touched day file is rebuilt whole.
    const last = st.lastRun ? new Date(st.lastRun) : new Date(now.getTime() - (opts.backfillDays ?? 7) * 86_400_000);
    const from = startOfDay(last);
    step.state = "running";
    step.since = stamp();
    step.line = `${source.title} 수집 중`;
    progress.current = { name: source.name, title: source.title, line: step.line };
    beat();
    try {
      const { days, note: summary } = await source.collect({ from, to: now, settings, config: cfg, log: note, tick: beat });
      const dir = join(cfg.worklogDir, "sources", source.name);
      await mkdir(dir, { recursive: true });
      for (const [day, body] of Object.entries(days)) if (body.trim()) await writeDay(dir, source.name, day, body, source.append === true);
      Object.assign(st, { lastRun: now.toISOString(), lastOk: true, lastError: undefined, lastNote: summary });
      step.state = "done";
      step.note = summary;
      report.push({ name: source.name, ok: true, days: Object.keys(days).sort(), note: summary });
    } catch (err) {
      const msg = (err as Error).message;
      Object.assign(st, { lastOk: false, lastError: msg, lastErrorAt: now.toISOString() });
      step.state = "failed";
      step.error = msg;
      report.push({ name: source.name, ok: false, days: [], error: msg });
    }
    progress.current = null;
    beat();
  }
  saveState(state);
  return report;
}
