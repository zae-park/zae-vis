#!/usr/bin/env node
// `zaevis daily` / `zaevis collect`: run the data-source connectors, then refresh the search index.
//
//   node src/daily.ts [--if-stale] [--source NAME]... [--no-index] [--json]

import { existsSync } from "node:fs";
import { loadConfig, loadState, saveState } from "./config.ts";
import { AutoRAGMcp } from "./autorag.ts";
import { EmbeddingDaemon } from "./embedding.ts";
import { isStale } from "./schedule.ts";
import { collect } from "./sources/index.ts";

async function refreshIndex(autoragConfig: string, worklogDir: string, localEmbedding: boolean): Promise<string> {
  if (!existsSync(autoragConfig)) return "건너뜀 (AutoRAG 미설정)";
  if (localEmbedding) {
    // The app's server keeps a daemon while it runs; when it is closed, start one that exits after a
    // few idle minutes so the nightly refresh still gets vectors. AutoRAG adopts whichever is running.
    const d = new EmbeddingDaemon({ idleTimeout: 300, detached: true, log: (m) => console.log(`  ${m}`) });
    const s = await d.start();
    if (s.state !== "ready") console.log(`  · 임베딩 데몬 없음 — 키워드 색인만: ${s.error ?? s.state}`);
  }
  const rag = new AutoRAGMcp({ configPath: autoragConfig, roots: [worklogDir] });
  try {
    await rag.refresh(false);
    return "완료";
  } finally {
    await rag.close();
  }
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  const only: string[] = [];
  for (let i = 0; i < argv.length; i++) if (argv[i] === "--source" && argv[i + 1]) only.push(argv[++i]);
  const cfg = loadConfig();
  const ts = () => new Date().toLocaleString("sv-SE");

  if (argv.includes("--if-stale")) {
    const last = loadState().daily?.lastRun;
    if (!isStale(last ? new Date(last) : null, cfg.dailyAt)) {
      console.log(`[${ts()}] 오늘 수집은 이미 끝났습니다. 건너뜀.`);
      return;
    }
  }
  if (!existsSync(cfg.worklogDir)) {
    console.error(`worklog 폴더가 없습니다: ${cfg.worklogDir} — 'zaevis setup'을 먼저 실행하세요.`);
    process.exitCode = 1;
    return;
  }

  console.log(`[${ts()}] 수집 시작`);
  const report = await collect(cfg, { only: only.length ? only : undefined, log: (m) => console.log(`  · ${m}`) });
  for (const r of report) {
    console.log(r.ok ? `  ✓ ${r.name}: ${r.note ?? ""}${r.days.length ? ` (${r.days.join(", ")})` : ""}` : `  ✗ ${r.name}: ${r.error}`);
  }

  let index = "건너뜀";
  if (!argv.includes("--no-index")) {
    console.log(`[${ts()}] 색인 갱신`);
    try {
      index = await refreshIndex(cfg.autoragConfig, cfg.worklogDir, cfg.localEmbedding);
    } catch (err) {
      index = `실패: ${(err as Error).message}`;
      process.exitCode = 1;
    }
    console.log(`  색인: ${index}`);
  }

  if (!only.length) {
    const state = loadState();
    state.daily = { lastRun: new Date().toISOString(), ok: report.every((r) => r.ok), index };
    saveState(state);
  }
  if (argv.includes("--json")) console.log(JSON.stringify({ report, index }));
  console.log(`[${ts()}] 끝`);
}

await main();
