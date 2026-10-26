#!/usr/bin/env node
// Entry point: `node src/main.ts` (Node >= 24 runs TypeScript directly). Normally started by `zaevis`.
//
// Settings: ~/.zaevis/config.json (kit/setup.sh), ~/.zaevis/sources.json (data sources).
// Env overrides: ZAEVIS_HOME, WORKLOG_DIR, AUTORAG_CONFIG, ZAEVIS_PORT, ZAEVIS_WEB_DIR.

import { existsSync } from "node:fs";
import { join } from "node:path";
import { AutoRAGMcp } from "./autorag.ts";
import { createApp } from "./app.ts";
import { addCustomSource, loadConfig, loadSources, loadState, removeCustomSource, saveAppSettings, saveSourceSettings, saveState } from "./config.ts";
import { DigestRunner, detectAgents, pickAgent } from "./digest.ts";
import { EmbeddingDaemon } from "./embedding.ts";
import * as rerank from "./rerank.ts";
import { installSchedule, scheduleStatus } from "./schedule.ts";
import { collect, listSources } from "./sources/index.ts";
import { TranscribeQueue, whisperxBin } from "./transcribe.ts";
import { Worklog } from "./worklog.ts";

let cfg = loadConfig();
if (!existsSync(cfg.worklogDir)) {
  console.error(`worklog folder not found: ${cfg.worklogDir}\nRun 'zaevis setup' first or set WORKLOG_DIR.`);
  process.exit(1);
}

// The search child only sees the OpenRouter key while re-ranking is turned on.
const search = new AutoRAGMcp({ configPath: cfg.autoragConfig, roots: [cfg.worklogDir], env: () => rerank.childEnv(cfg.rerank) });
// Keep AutoRAG's config in step with the setting (also clears the lite-init defaults on first start).
rerank.applyToAutoragConfig(cfg.autoragConfig, cfg.rerank, rerank.getKey() !== null);
// Semantic search: a local embedding daemon the server keeps alive (idle-timeout 0) while it runs.
const embedding = new EmbeddingDaemon({ idleTimeout: 0, log: (m) => console.log(m) });
const queue = new TranscribeQueue();
const digest = new DigestRunner();
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
    recordDaily: ({ ok, index }) => {
      const state = loadState();
      state.daily = { lastRun: new Date().toISOString(), ok, index };
      saveState(state);
    },
  },
  settings: {
    async get() {
      const ts = transcriptSettings();
      return {
        dailyAt: cfg.dailyAt,
        indexOnInject: cfg.indexOnInject,
        worklogDir: cfg.worklogDir,
        schedule: await scheduleStatus(cfg.dailyAt),
        lastDaily: loadState().daily ?? null,
        whisperx: whisperxBin(ts.whisperxBin as string | undefined) !== null,
        localEmbedding: cfg.localEmbedding,
        rerank: rerank.status(cfg.rerank),
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
  digest: {
    async status() {
      const agents = await detectAgents();
      const chosen = pickAgent(cfg.digest, agents);
      return { ...digest.status(cfg.digest, cfg.worklogDir), setting: cfg.digest, agents, chosen: chosen?.id ?? null };
    },
    async update(patch) {
      const agent = (["auto", "claude", "codex", "gemini", "openrouter"] as const).find((a) => a === patch.agent) ?? cfg.digest.agent;
      saveAppSettings({ digest: { agent, model: patch.model ?? cfg.digest.model, weekly: patch.weekly ?? cfg.digest.weekly } });
      cfg = loadConfig();
      return this.status();
    },
    async run() {
      const chosen = pickAgent(cfg.digest, await detectAgents());
      if (!chosen) return { started: false, reason: "쓸 수 있는 에이전트가 없습니다. Claude Code·Codex·Gemini CLI 중 하나를 설치하거나 설정에서 OpenRouter 키를 저장하세요." };
      if (digest.status(cfg.digest, cfg.worklogDir).running) return { started: false, reason: "이미 정리가 실행 중입니다." };
      void digest.run(cfg, cfg.digest, chosen);
      return { started: true };
    },
  },
  rerank: {
    status: () => rerank.status(cfg.rerank),
    async update(patch) {
      if (patch.apiKey !== undefined) rerank.setKey(patch.apiKey);
      const next = { enabled: patch.enabled ?? cfg.rerank.enabled, model: patch.model || cfg.rerank.model };
      saveAppSettings({ rerank: next });
      cfg = loadConfig();
      rerank.applyToAutoragConfig(cfg.autoragConfig, cfg.rerank, rerank.getKey() !== null);
      await search.restart();
      return rerank.status(cfg.rerank);
    },
    test: (apiKey) => rerank.testKey(apiKey ?? rerank.getKey() ?? ""),
  },
  embedding: {
    status: async () => embedding.health(),
    set: async (enabled) => {
      if (!enabled) {
        await embedding.stop();
        return false;
      }
      const was = embedding.current.state;
      const s = await embedding.start();
      const became = s.state === "ready" && was !== "ready";
      if (became) {
        const state = loadState();
        state.embedding = { model: s.model ?? "", builtAt: new Date().toISOString() };
        saveState(state);
      }
      return became;
    },
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
  if (cfg.localEmbedding) void startEmbeddingAtBoot();
});

/** Starts the daemon; the first time a model is available, rebuilds the index so existing chunks get vectors. */
async function startEmbeddingAtBoot(): Promise<void> {
  const s = await embedding.start();
  if (s.state !== "ready") {
    if (s.state === "failed") console.error(`[embedding] ${s.error}`);
    return;
  }
  const state = loadState();
  if (state.embedding?.model === s.model) return;
  console.log(`[embedding] first run with ${s.model}: rebuilding the index so every chunk gets a vector`);
  try {
    const res = await fetch(`http://127.0.0.1:${cfg.port}/api/index`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-zaevis": "1" },
      body: JSON.stringify({ force: true }),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    state.embedding = { model: s.model ?? "", builtAt: new Date().toISOString() };
    saveState(state);
  } catch (err) {
    console.error(`[embedding] rebuild request failed: ${(err as Error).message}`);
  }
}

const shutdown = async () => {
  server.close();
  await embedding.stop();
  await search.close();
  process.exit(0);
};
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
