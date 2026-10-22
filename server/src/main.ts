#!/usr/bin/env node
// Entry point: `node src/main.ts` (Node >= 24 runs TypeScript directly).
//
// Settings come from ~/.worklog-kit/config.json (written by kit/setup.sh) and can be
// overridden with env vars: WORKLOG_DIR, AUTORAG_CONFIG, WORKLOG_PORT, WORKLOG_WEB_DIR.

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { AutoRAGMcp } from "./autorag.ts";
import { createApp } from "./app.ts";
import { Worklog } from "./worklog.ts";

type FileConfig = { worklogDir?: string; autoragConfig?: string; port?: number };

const expand = (p: string) => (p.startsWith("~/") ? join(homedir(), p.slice(2)) : p);

function loadConfig(): Required<FileConfig> & { webDir: string | null } {
  const file = join(homedir(), ".worklog-kit", "config.json");
  const fc: FileConfig = existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : {};
  const worklogDir = expand(process.env.WORKLOG_DIR ?? fc.worklogDir ?? "~/worklog");
  const here = dirname(fileURLToPath(import.meta.url));
  const bundledWeb = resolve(here, "..", "..", "app", "build", "web");
  const webDir = process.env.WORKLOG_WEB_DIR ?? (existsSync(bundledWeb) ? bundledWeb : null);
  return {
    worklogDir: resolve(worklogDir),
    autoragConfig: expand(process.env.AUTORAG_CONFIG ?? fc.autoragConfig ?? "~/.autorag/config.json"),
    port: Number(process.env.WORKLOG_PORT ?? fc.port ?? 4710),
    webDir,
  };
}

const cfg = loadConfig();
if (!existsSync(cfg.worklogDir)) {
  console.error(`worklog folder not found: ${cfg.worklogDir}\nRun kit/setup.sh first or set WORKLOG_DIR.`);
  process.exit(1);
}

const search = new AutoRAGMcp({ configPath: cfg.autoragConfig, roots: [cfg.worklogDir] });
const server = createApp({ worklog: new Worklog(cfg.worklogDir), search, webDir: cfg.webDir });

server.listen(cfg.port, "127.0.0.1", () => {
  console.log(`worklog-kit server  http://127.0.0.1:${cfg.port}`);
  console.log(`  worklog : ${cfg.worklogDir}`);
  console.log(`  autorag : ${cfg.autoragConfig}`);
  console.log(`  web app : ${cfg.webDir ?? "(not built — run: cd app && flutter build web)"}`);
});

const shutdown = async () => {
  server.close();
  await search.close();
  process.exit(0);
};
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
