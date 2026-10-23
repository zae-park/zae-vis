#!/usr/bin/env node
// Entry point: `node src/main.ts` (Node >= 24 runs TypeScript directly). Normally started by `zaevis`.
//
// Settings: ~/.zaevis/config.json (kit/setup.sh), ~/.zaevis/sources.json (data sources).
// Env overrides: ZAEVIS_HOME, WORKLOG_DIR, AUTORAG_CONFIG, ZAEVIS_PORT, ZAEVIS_WEB_DIR.

import { existsSync } from "node:fs";
import { join } from "node:path";
import { AutoRAGMcp } from "./autorag.ts";
import { createApp } from "./app.ts";
import { addCustomSource, loadConfig, loadSources, loadState, removeCustomSource, saveAppSettings, saveSourceSettings } from "./config.ts";
import { installSchedule, scheduleStatus } from "./schedule.ts";
import { collect, listSources } from "./sources/index.ts";
import { TranscribeQueue, whisperxBin } from "./transcribe.ts";
import { Worklog } from "./worklog.ts";

let cfg = loadConfig();
if (!existsSync(cfg.worklogDir)) {
  console.error(`worklog folder not found: ${cfg.worklogDir}\nRun 'zaevis setup' first or set WORKLOG_DIR.`);
  process.exit(1);
}

const search = new AutoRAGMcp({ configPath: cfg.autoragConfig, roots: [cfg.worklogDir] });
const queue = new TranscribeQueue();
const transcriptSettings = () => loadSources(cfg).transcripts ?? { enabled: true };

const server = createApp({
  worklog: new Worklog(cfg.worklogDir),
  search,
  webDir: cfg.webDir,
  sources: {
    list: () => listSources(cfg),
    collect: (only) => collect(cfg, { only, log: (m) => console.log(`[collect] ${m}`) }),
    update: (name, patch) => saveSourceSettings(name, patch),
    add: (src) => addCustomSource(src),
    remove: (name) => removeCustomSource(name),
  },
  settings: {
    async get() {
      const ts = transcriptSettings();
      return {
        dailyAt: cfg.dailyAt,
        indexOnInject: cfg.indexOnInject,
        worklogDir: cfg.worklogDir,
        schedule: await scheduleStatus(),
        lastDaily: loadState().daily ?? null,
        whisperx: whisperxBin(ts.whisperxBin as string | undefined) !== null,
      };
    },
    async update(patch) {
      saveAppSettings(patch);
      cfg = loadConfig();
      if (patch.dailyAt !== undefined) {
        const st = await scheduleStatus();
        if (st.supported) await installSchedule(cfg.dailyAt);
      }
      return this.get();
    },
    indexOnInject: () => cfg.indexOnInject,
  },
  audio: {
    dir: () => String(transcriptSettings().audioDir ?? join(cfg.worklogDir, "inbox", "audio")),
    enqueue: (file) => {
      const ts = transcriptSettings();
      queue.enqueue(file, cfg.worklogDir, { language: String(ts.language ?? "ko"), model: String(ts.model ?? "large-v3-turbo"), whisperxBin: ts.whisperxBin as string | undefined });
    },
    jobs: () => queue.jobs,
  },
});

server.listen(cfg.port, "127.0.0.1", () => {
  console.log(`zaevis server  http://127.0.0.1:${cfg.port}`);
  console.log(`  worklog : ${cfg.worklogDir}`);
  console.log(`  autorag : ${cfg.autoragConfig}`);
  console.log(`  web app : ${existsSync(join(cfg.webDir, "index.html")) ? cfg.webDir : "(not built — run: zaevis run web)"}`);
});

const shutdown = async () => {
  server.close();
  await search.close();
  process.exit(0);
};
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
