// HTTP API for the Flutter front-end. Binds to loopback only; see main.ts.

import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { createWriteStream } from "node:fs";
import { mkdir, readFile, rm, stat } from "node:fs/promises";
import { basename, extname, join, normalize, sep } from "node:path";
import type { AskOutcome } from "./ask.ts";
import type { RefreshPhase, SearchBackend } from "./autorag.ts";
import { AUDIO_EXT } from "./transcribe.ts";
import { freePath, safeStem, type Worklog } from "./worklog.ts";

export type CollectReportLike = Array<{ name: string; ok: boolean; days: string[]; note?: string; error?: string }>;

export type AppOptions = {
  worklog: Worklog;
  search: SearchBackend;
  webDir?: string | null; // built Flutter web app (app/build/web), served at "/"
  /** Optional features; absent in minimal tests. */
  sources?: {
    list(): unknown[];
    collect(only?: string[]): Promise<CollectReportLike>;
    update(name: string, patch: Record<string, unknown>): void;
    add(src: { name: string; command: string; description?: string }): void;
    remove(name: string): boolean;
    /** A full collect (+ index) from the API counts as the daily run — so `daily --if-stale` does not repeat it. */
    recordDaily?(result: { ok: boolean; index: string }): void;
  };
  settings?: {
    get(): Promise<Record<string, unknown>>;
    update(patch: { dailyAt?: string; indexOnInject?: boolean; localEmbedding?: boolean; notifications?: boolean; hotkey?: string }): Promise<Record<string, unknown>>;
    indexOnInject(): boolean;
  };
  /** Weekly digest: agents found on this machine and the run itself. */
  digest?: {
    status(): Promise<Record<string, unknown>>;
    update(patch: { agent?: string; model?: string; weekly?: boolean; review?: boolean }): Promise<Record<string, unknown>>;
    /** Starts a run in the background; `started: false` with a reason when nothing can run. */
    run(): Promise<{ started: boolean; reason?: string }>;
    /** Review flow: proposals a run left for the user to approve. */
    proposals(): Promise<unknown[]>;
    proposal(id: string): Promise<unknown | null>;
    /** `apply` with a selection, or `dismiss`. Null when the proposal does not exist or is not pending. */
    act(id: string, body: Record<string, unknown>): Promise<Record<string, unknown> | null>;
  };
  /** "질문": an answer written from the top search passages by an agent the user has (see ask.ts). */
  ask?: {
    /** Agents, which one would answer, whether one is answering now, and the last answer. */
    status(): Promise<Record<string, unknown>>;
    run(q: string, topK?: number, conversationId?: string): Promise<AskOutcome>;
    /** One conversation with its turns, or null. */
    conversation(id: string): unknown | null;
    remove(id: string): boolean;
  };
  /** Optional OpenRouter re-ranking of search results. */
  rerank?: {
    status(): Record<string, unknown>;
    /** Saves setting/key (apiKey "" removes the key), rewrites AutoRAG's config, restarts the search child. */
    update(patch: { enabled?: boolean; model?: string; apiKey?: string }): Promise<Record<string, unknown>>;
    test(apiKey?: string): Promise<{ ok: boolean; message: string }>;
  };
  /** Local embedding daemon (semantic search); absent when minsync is not managed here. */
  embedding?: {
    status(): Promise<Record<string, unknown>>;
    /** Returns true when the daemon just became ready (caller re-indexes so vectors get built). */
    set(enabled: boolean): Promise<boolean>;
  };
  /** Korean morphological tokenizer (Kiwi) for BM25: status, child restart when it appears, rebuild bookkeeping (kiwi.ts). */
  tokenizer?: {
    sync(canRestart: boolean): Promise<Record<string, unknown>>;
    refreshed(force: boolean, ok: boolean): void;
  };
  audio?: {
    dir(): string;
    enqueue(file: string): void;
    jobs(): unknown[];
  };
  /** External AutoRAG datasources (Slack, Obsidian, GitHub …) — see datasources.ts. */
  datasources?: {
    /** Every template with its probe + config + what AutoRAG has loaded. */
    list(): Promise<unknown[]>;
    /** Creates/updates a connection in AutoRAG's config and restarts the search child. Throws on bad input (→ 400). */
    save(name: string, patch: Record<string, unknown>): Promise<{ enabled: boolean }>;
    remove(name: string): Promise<boolean>;
    /** The original behind an external hit ("/obsidian/default/노트.md"), when it is a local file. */
    file(path: string): Promise<{ path: string; markdown: string } | null>;
    /** Outcome of a `datasources` refresh phase (AutoRAG's result, or the error). */
    recordSync(result: unknown, error?: string): void;
  };
  /** Daily / weekly / monthly reports written by an agent from the period's records — see reports.ts. */
  reports?: {
    /** Setting, the run in progress, the last run per kind, every report on disk, default periods. */
    status(): Promise<Record<string, unknown>>;
    /** One report (`markdown` without its front matter), or null. */
    read(kind: string, period: string): Promise<Record<string, unknown> | null>;
    /** Saves a settings patch and returns the status. Throws on a bad value (→ 400). */
    update(patch: Record<string, unknown>): Promise<Record<string, unknown>>;
    /** Starts a run in the background; `started: false` with an error code and reason when it cannot. */
    run(kind: string, period?: string): Promise<{ started: boolean; status?: number; error?: string; reason?: string; kind?: string; period?: string; agent?: string }>;
  };
};

const MIME: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".svg": "image/svg+xml",
  ".wasm": "application/wasm",
  ".otf": "font/otf",
  ".ttf": "font/ttf",
};

// `flutter run -d chrome` serves the app from a random localhost port.
const LOCAL_ORIGIN = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/;
const LOCAL_HOST = /^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/;
const MAX_AUDIO = 1024 * 1024 * 1024; // 1 GB

function send(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(body));
}

/** null/false instead of a throw, for lookups whose argument came from the URL. */
function safe<T>(f: () => T): T | null {
  try {
    return f();
  } catch {
    return null;
  }
}

const notFound = (res: ServerResponse) => send(res, 404, { error: "not_found" });

class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

async function readJson(req: IncomingMessage, limit = 64 * 1024): Promise<Record<string, unknown>> {
  let body = "";
  for await (const chunk of req) {
    body += chunk;
    if (body.length > limit) throw new HttpError(413, "요청이 너무 큽니다");
  }
  if (!body) return {};
  const v = JSON.parse(body);
  return v && typeof v === "object" ? v : {};
}

async function serveStatic(webDir: string, urlPath: string, res: ServerResponse): Promise<boolean> {
  const rel = normalize(decodeURIComponent(urlPath)).replace(/^([/\\])+/, "");
  let file = join(webDir, rel);
  if (!file.startsWith(webDir + sep) && file !== webDir) return false;
  try {
    if ((await stat(file)).isDirectory()) file = join(file, "index.html");
  } catch {
    file = join(webDir, "index.html"); // SPA fallback
  }
  try {
    const data = await readFile(file);
    res.writeHead(200, { "content-type": MIME[extname(file)] ?? "application/octet-stream" });
    res.end(data);
    return true;
  } catch {
    return false;
  }
}

export function createApp(opts: AppOptions): Server {
  const { worklog, search } = opts;
  let refreshing: Promise<unknown> | null = null;
  let lastRefresh: { finishedAt: string; ok: boolean; error?: string } | null = null;
  let collecting: Promise<unknown> | null = null;
  let lastCollect: { finishedAt: string; report: CollectReportLike; error?: string } | null = null;

  function startRefresh(force: boolean, phases?: RefreshPhase[]): void {
    if (refreshing) return;
    const external = phases?.includes("datasources") ?? true; // a full refresh syncs the external connections too
    refreshing = search
      .refresh(force, phases)
      .then((result) => {
        lastRefresh = { finishedAt: new Date().toISOString(), ok: true };
        opts.tokenizer?.refreshed(force, true);
        if (external) opts.datasources?.recordSync(result);
      })
      .catch((err: unknown) => {
        const error = String((err as Error)?.message ?? err);
        lastRefresh = { finishedAt: new Date().toISOString(), ok: false, error };
        opts.tokenizer?.refreshed(force, false);
        if (external) opts.datasources?.recordSync(null, error);
      })
      .finally(() => {
        refreshing = null;
      });
  }

  return createServer(async (req, res) => {
    const origin = req.headers.origin;
    if (origin && LOCAL_ORIGIN.test(origin)) {
      res.setHeader("access-control-allow-origin", origin);
      res.setHeader("vary", "origin");
      res.setHeader("access-control-allow-headers", "content-type, x-zaevis");
      res.setHeader("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS");
    }
    // Only this machine may talk to the server: reject other sites (CSRF) and rebound host names.
    if (!LOCAL_HOST.test(req.headers.host ?? "")) return send(res, 403, { error: "forbidden_host" });
    if (req.method !== "GET" && req.method !== "OPTIONS") {
      if (origin && !LOCAL_ORIGIN.test(origin)) return send(res, 403, { error: "forbidden_origin" });
      if (req.headers["x-zaevis"] !== "1") return send(res, 403, { error: "missing_x_zaevis_header" });
    }
    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    const url = new URL(req.url ?? "/", "http://localhost");
    const parts = url.pathname.split("/").filter(Boolean).map(decodeURIComponent);

    try {
      if (parts[0] !== "api") {
        if (req.method === "GET" && opts.webDir && (await serveStatic(opts.webDir, url.pathname, res))) return;
        if (req.method === "GET" && url.pathname === "/") {
          res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
          res.end("웹 앱이 아직 빌드되지 않았습니다. 터미널에서 `zaevis run web`을 실행하세요.\n");
          return;
        }
        return notFound(res);
      }

      const route = `${req.method} /${parts.slice(1, 2).join("/")}`;
      const arg = parts[2];

      switch (route) {
        case "GET /health":
          return send(res, 200, { ok: true, worklog: worklog.root, build: process.env.ZAEVIS_BUILD ?? null });

        case "GET /logs":
          if (arg === undefined) return send(res, 200, { months: await worklog.months("log") });
          {
            const entries = await worklog.log(arg);
            return entries === null ? notFound(res) : send(res, 200, { month: arg, entries });
          }

        case "GET /summaries":
          if (arg === undefined) return send(res, 200, { months: await worklog.months("summaries") });
          {
            const markdown = await worklog.summary(arg);
            return markdown === null ? notFound(res) : send(res, 200, { month: arg, markdown });
          }

        case "GET /projects":
          if (arg === undefined) return send(res, 200, { projects: await worklog.projects() });
          {
            const project = await worklog.project(arg);
            return project === null ? notFound(res) : send(res, 200, project);
          }

        case "GET /search": {
          const q = (url.searchParams.get("q") ?? "").trim();
          if (!q) return send(res, 400, { error: "missing_query" });
          const topK = Math.min(Math.max(Number(url.searchParams.get("topK")) || 10, 1), 50);
          return send(res, 200, await search.search(q, topK));
        }

        case "GET /ask": {
          // GET /api/ask → agents, running, last, conversations[]  ·  GET /api/ask/:id → one conversation with its turns
          if (!opts.ask) return notFound(res);
          if (!arg) return send(res, 200, await opts.ask.status());
          const c = safe(() => opts.ask!.conversation(arg)); // a malformed id is just "not found"
          return c ? send(res, 200, c) : notFound(res);
        }

        case "DELETE /ask":
          if (!opts.ask || !arg) return notFound(res);
          return safe(() => opts.ask!.remove(arg)) ? send(res, 200, { ok: true }) : notFound(res);

        case "POST /ask": {
          // POST /api/ask { q, topK?, conversationId? } → { answer, sources[{ n, path, label, passage }], agent, ms, conversationId, turn }
          if (!opts.ask || arg) return notFound(res);
          const b = await readJson(req);
          const q = typeof b.q === "string" ? b.q.trim() : "";
          if (!q) return send(res, 400, { error: "missing_query", message: "질문을 입력하세요." });
          const topK = typeof b.topK === "number" && Number.isFinite(b.topK) ? b.topK : undefined;
          const conversationId = typeof b.conversationId === "string" && b.conversationId ? b.conversationId : undefined;
          const r = await opts.ask.run(q, topK, conversationId);
          if (!r.ok) return send(res, r.status, { error: r.error, message: r.message });
          return send(res, 200, r.result);
        }

        case "GET /origins":
          // GET /api/origins?limit= → { files[{ path, source, kind, date, name, bytes }] } newest first
          return send(res, 200, { files: await worklog.origins(Math.min(Math.max(Number(url.searchParams.get("limit")) || 400, 1), 2000)) });

        case "GET /origin": {
          // GET /api/origin?src=<the (src: …) text> → { paths[] } — the files a log line came from
          const src = (url.searchParams.get("src") ?? "").trim();
          if (!src) return send(res, 400, { error: "missing_src" });
          return send(res, 200, { src, paths: await worklog.resolveSource(src) });
        }

        case "GET /file": {
          const rel = (url.searchParams.get("path") ?? "").trim();
          if (!rel) return send(res, 400, { error: "missing_path" });
          // "/obsidian/default/노트.md" is an external datasource source, not a worklog file
          const f = rel.startsWith("/") && opts.datasources ? await opts.datasources.file(rel) : await worklog.file(rel);
          return f ? send(res, 200, f) : notFound(res);
        }

        case "GET /index":
          return send(res, 200, {
            refreshing: refreshing !== null,
            lastRefresh,
            autorag: await search.status(),
            ...(opts.embedding ? { embedding: await opts.embedding.status() } : {}),
            // `tokenizer`: multilingual (Kiwi morphemes) or whitespace, and whether a rebuild is owed
            ...(opts.tokenizer ? { tokenizer: await opts.tokenizer.sync(refreshing === null) } : {}),
          });

        case "POST /index": {
          const body = await readJson(req);
          // a Kiwi installed since the child started must reach it before this refresh
          if (refreshing === null) await opts.tokenizer?.sync(true);
          startRefresh(body.force === true);
          return send(res, 202, { refreshing: true });
        }

        case "POST /logs": {
          const b = await readJson(req);
          const date = typeof b.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(b.date) ? new Date(`${b.date}T12:00:00`) : undefined;
          const strs = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);
          let added;
          try {
            added = await worklog.appendLog({ text: String(b.text ?? ""), tags: strs(b.tags), projects: strs(b.projects), date });
          } catch (err) {
            throw new HttpError(400, (err as Error).message);
          }
          if (opts.settings?.indexOnInject()) startRefresh(false);
          return send(res, 201, added);
        }

        case "PUT /logs": {
          // PUT /api/logs/:month { raw, text?, tags?, projects?, date? } — edits one line by its current text
          if (!arg) return notFound(res);
          const b = await readJson(req);
          if (typeof b.raw !== "string" || !b.raw.trim()) throw new HttpError(400, "raw(현재 줄)가 필요합니다.");
          const strs = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : undefined);
          let r;
          try {
            r = await worklog.updateLog(arg, b.raw, {
              ...(typeof b.text === "string" ? { text: b.text } : {}),
              ...(strs(b.tags) ? { tags: strs(b.tags) } : {}),
              ...(strs(b.projects) ? { projects: strs(b.projects) } : {}),
              ...(typeof b.date === "string" ? { date: b.date } : {}),
            });
          } catch (err) {
            throw new HttpError(400, (err as Error).message);
          }
          if (!r) return send(res, 409, { error: "line_changed", message: "그 줄을 찾지 못했습니다. 파일이 바뀌었을 수 있으니 새로고침 뒤 다시 시도하세요." });
          if (opts.settings?.indexOnInject()) startRefresh(false);
          return send(res, 200, r);
        }

        case "DELETE /logs": {
          // DELETE /api/logs/:month { raw }
          if (!arg) return notFound(res);
          const b = await readJson(req);
          if (typeof b.raw !== "string" || !b.raw.trim()) throw new HttpError(400, "raw(현재 줄)가 필요합니다.");
          if (!(await worklog.deleteLog(arg, b.raw))) return send(res, 409, { error: "line_changed", message: "그 줄을 찾지 못했습니다. 새로고침 뒤 다시 시도하세요." });
          if (opts.settings?.indexOnInject()) startRefresh(false);
          return send(res, 200, { ok: true });
        }

        case "GET /inbox":
          return send(res, 200, { ...(await worklog.inbox()), jobs: opts.audio?.jobs() ?? [] });

        case "POST /inbox": {
          if (arg === "transcripts") {
            const b = await readJson(req, 5 * 1024 * 1024);
            let file;
            try {
              file = await worklog.saveTranscript(String(b.name ?? "memo"), String(b.text ?? ""));
            } catch (err) {
              throw new HttpError(400, (err as Error).message);
            }
            if (opts.settings?.indexOnInject()) startRefresh(false);
            return send(res, 201, { file: basename(file) });
          }
          if (arg === "audio" && opts.audio) {
            const name = url.searchParams.get("name") ?? "";
            const ext = extname(name).toLowerCase();
            if (!AUDIO_EXT.has(ext)) throw new HttpError(400, `지원하지 않는 형식입니다: ${ext || "(확장자 없음)"}`);
            const dir = opts.audio.dir();
            await mkdir(dir, { recursive: true });
            const dest = freePath(dir, safeStem(name), ext);
            let size = 0;
            const out = createWriteStream(dest);
            try {
              for await (const chunk of req) {
                size += (chunk as Buffer).length;
                if (size > MAX_AUDIO) throw new HttpError(413, "파일이 너무 큽니다 (최대 1GB)");
                if (!out.write(chunk)) await new Promise((r) => out.once("drain", r));
              }
              await new Promise<void>((r, j) => out.end((e?: Error | null) => (e ? j(e) : r())));
            } catch (err) {
              out.destroy();
              await rm(dest, { force: true });
              throw err;
            }
            opts.audio.enqueue(dest);
            return send(res, 202, { file: basename(dest), queued: true });
          }
          return notFound(res);
        }

        case "GET /sources":
          if (!opts.sources) return notFound(res);
          return send(res, 200, { sources: opts.sources.list(), collecting: collecting !== null, lastCollect });

        case "POST /sources": {
          if (!opts.sources) return notFound(res);
          const b = await readJson(req);
          const name = String(b.name ?? "").trim();
          const command = String(b.command ?? "").trim();
          if (!/^[a-z0-9][a-z0-9_-]{0,39}$/.test(name)) throw new HttpError(400, "이름은 영문 소문자·숫자·-·_ 로 40자 이내여야 합니다.");
          if (!command) throw new HttpError(400, "실행할 명령이 비어 있습니다.");
          try {
            opts.sources.add({ name, command, description: typeof b.description === "string" ? b.description : undefined });
          } catch (err) {
            throw new HttpError(409, (err as Error).message);
          }
          return send(res, 201, { ok: true });
        }

        case "PUT /sources": {
          if (!opts.sources || !arg) return notFound(res);
          const b = await readJson(req);
          const patch: Record<string, unknown> = {};
          if (typeof b.enabled === "boolean") patch.enabled = b.enabled;
          if (b.settings && typeof b.settings === "object") Object.assign(patch, b.settings);
          delete patch.name;
          opts.sources.update(arg, patch);
          return send(res, 200, { ok: true });
        }

        case "DELETE /sources":
          if (!opts.sources || !arg) return notFound(res);
          return opts.sources.remove(arg) ? send(res, 200, { ok: true }) : send(res, 400, { error: "기본 데이터소스는 끌 수만 있고 지울 수 없습니다." });

        // ── external AutoRAG datasources ──────────────────────────────────
        case "GET /datasources":
          // GET /api/datasources → { datasources[], syncing, lastRefresh }
          if (!opts.datasources || arg) return notFound(res);
          return send(res, 200, { datasources: await opts.datasources.list(), syncing: refreshing !== null, lastRefresh });

        case "PUT /datasources": {
          // PUT /api/datasources/:name { enabled?, description?, type?, connector?, channels? } — then syncs the connections
          if (!opts.datasources || !arg) return notFound(res);
          const b = await readJson(req);
          const patch: Record<string, unknown> = {};
          if (typeof b.enabled === "boolean") patch.enabled = b.enabled;
          if (typeof b.description === "string") patch.description = b.description;
          if (typeof b.type === "string" && b.type) patch.type = b.type;
          if (b.connector && typeof b.connector === "object" && !Array.isArray(b.connector)) patch.connector = b.connector;
          if (b.channels && typeof b.channels === "object" && !Array.isArray(b.channels)) patch.channels = b.channels;
          if (b.secrets && typeof b.secrets === "object" && !Array.isArray(b.secrets)) patch.secrets = b.secrets;
          let saved;
          try {
            saved = await opts.datasources.save(arg, patch);
          } catch (err) {
            throw new HttpError(400, (err as Error).message);
          }
          if (saved.enabled && b.sync !== false) startRefresh(false, ["datasources"]);
          return send(res, 200, { ok: true, syncing: refreshing !== null });
        }

        case "DELETE /datasources":
          if (!opts.datasources || !arg) return notFound(res);
          return (await opts.datasources.remove(arg)) ? send(res, 200, { ok: true }) : notFound(res);

        case "POST /datasources": {
          // POST /api/datasources/:name/sync — AutoRAG syncs every enabled connection (there is no per-connection refresh)
          if (!opts.datasources || !arg || parts[3] !== "sync") return notFound(res);
          if (refreshing) return send(res, 409, { error: "busy", message: "이미 색인이 진행 중입니다. 끝난 뒤 다시 시도하세요." });
          startRefresh(false, ["datasources"]);
          return send(res, 202, { syncing: true });
        }

        case "GET /collect":
          return send(res, 200, { collecting: collecting !== null, lastCollect });

        case "POST /collect": {
          if (!opts.sources) return notFound(res);
          const b = await readJson(req);
          const only = Array.isArray(b.sources) ? b.sources.filter((x): x is string => typeof x === "string") : undefined;
          const withIndex = b.index !== false;
          if (!collecting) {
            const srcs = opts.sources;
            const full = !only || only.length === 0;
            collecting = srcs
              .collect(only)
              .then((report) => {
                lastCollect = { finishedAt: new Date().toISOString(), report };
                if (withIndex) startRefresh(false);
                return report;
              })
              .catch((err: unknown) => {
                lastCollect = { finishedAt: new Date().toISOString(), report: [], error: String((err as Error)?.message ?? err) };
                return null;
              })
              .finally(() => {
                collecting = null;
              })
              .then(async (report) => {
                if (!full || !report) return;
                let index = "건너뜀";
                if (withIndex) {
                  await refreshing;
                  index = lastRefresh?.ok ? "완료" : `실패: ${lastRefresh?.error ?? "?"}`;
                }
                srcs.recordDaily?.({ ok: report.every((r) => r.ok), index });
              });
          }
          return send(res, 202, { collecting: true });
        }

        case "GET /settings":
          if (!opts.settings) return notFound(res);
          return send(res, 200, await opts.settings.get());

        // ── reports ─────────────────────────────────────────────────────────
        case "GET /reports": {
          // GET /api/reports → { setting, running, lastRun, reports{daily[],weekly[],monthly[]}, defaults }  ·  GET /api/reports/:kind/:period → the report
          if (!opts.reports) return notFound(res);
          if (!arg) return send(res, 200, await opts.reports.status());
          if (!parts[3]) return notFound(res);
          const r = await opts.reports.read(arg, parts[3]);
          return r ? send(res, 200, r) : notFound(res);
        }

        case "PUT /reports": {
          // PUT /api/reports/settings { daily?: { enabled?, days? }, weekly?: { enabled?, day? }, monthly?: { enabled?, day? } }
          if (!opts.reports || arg !== "settings") return notFound(res);
          const b = await readJson(req);
          try {
            return send(res, 200, await opts.reports.update(b));
          } catch (err) {
            throw new HttpError(400, (err as Error).message);
          }
        }

        case "POST /reports": {
          // POST /api/reports/run { kind, period? } → 202 { started, kind, period, agent } · 409 busy / no_agent · 400 bad kind or period
          if (!opts.reports || arg !== "run") return notFound(res);
          const b = await readJson(req);
          const r = await opts.reports.run(String(b.kind ?? ""), typeof b.period === "string" && b.period ? b.period : undefined);
          return send(res, r.started ? 202 : (r.status ?? 409), r);
        }

        case "GET /digest": {
          if (!opts.digest) return notFound(res);
          if (arg === "proposals") {
            // GET /api/digest/proposals · GET /api/digest/proposals/:id
            const id = parts[3];
            if (!id) return send(res, 200, { proposals: await opts.digest.proposals() });
            const p = await opts.digest.proposal(id);
            return p ? send(res, 200, p) : notFound(res);
          }
          if (arg) return notFound(res);
          return send(res, 200, await opts.digest.status());
        }

        case "PUT /digest": {
          if (!opts.digest) return notFound(res);
          const b = await readJson(req);
          const patch: { agent?: string; model?: string; weekly?: boolean; review?: boolean } = {};
          if (typeof b.agent === "string") patch.agent = b.agent;
          if (typeof b.model === "string") patch.model = b.model.trim();
          if (typeof b.weekly === "boolean") patch.weekly = b.weekly;
          if (typeof b.review === "boolean") patch.review = b.review;
          return send(res, 200, await opts.digest.update(patch));
        }

        case "POST /digest": {
          if (!opts.digest) return notFound(res);
          if (arg === "run") {
            const r = await opts.digest.run();
            return send(res, r.started ? 202 : 409, r);
          }
          if (arg === "proposals" && parts[3]) {
            // POST /api/digest/proposals/:id { action: "apply", lines?, projects?, summaries?, processed? } | { action: "dismiss" }
            const b = await readJson(req);
            const r = await opts.digest.act(parts[3], b);
            return r ? send(res, 200, r) : send(res, 409, { error: "not_pending", message: "검토할 제안이 없거나 이미 처리됐습니다." });
          }
          return notFound(res);
        }

        case "POST /settings": {
          // POST /api/settings/rerank/test — checks a key with OpenRouter without saving it
          if (arg !== "rerank" || parts[3] !== "test" || !opts.rerank) return notFound(res);
          const b = await readJson(req);
          return send(res, 200, await opts.rerank.test(typeof b.apiKey === "string" ? b.apiKey : undefined));
        }

        case "PUT /settings": {
          if (arg === "rerank") {
            // PUT /api/settings/rerank { enabled?, model?, apiKey? } — apiKey "" removes the stored key
            if (!opts.rerank) return notFound(res);
            const b = await readJson(req);
            const patch: { enabled?: boolean; model?: string; apiKey?: string } = {};
            if (typeof b.enabled === "boolean") patch.enabled = b.enabled;
            if (typeof b.model === "string") patch.model = b.model.trim();
            if (typeof b.apiKey === "string") patch.apiKey = b.apiKey;
            return send(res, 200, await opts.rerank.update(patch));
          }
          if (arg) return notFound(res);
          if (!opts.settings) return notFound(res);
          const b = await readJson(req);
          const patch: { dailyAt?: string; indexOnInject?: boolean; localEmbedding?: boolean; notifications?: boolean; hotkey?: string } = {};
          if (typeof b.dailyAt === "string") patch.dailyAt = b.dailyAt;
          if (typeof b.indexOnInject === "boolean") patch.indexOnInject = b.indexOnInject;
          if (typeof b.localEmbedding === "boolean") patch.localEmbedding = b.localEmbedding;
          if (typeof b.notifications === "boolean") patch.notifications = b.notifications;
          if (typeof b.hotkey === "string" && /^[a-z0-9+]{0,60}$/i.test(b.hotkey)) patch.hotkey = b.hotkey; // "meta+shift+space", "" = default
          try {
            const out = await opts.settings.update(patch);
            if (patch.localEmbedding !== undefined && opts.embedding) {
              // Existing chunks have no vectors until a full re-index, so rebuild once the daemon is up.
              if (await opts.embedding.set(patch.localEmbedding)) startRefresh(true);
            }
            return send(res, 200, out);
          } catch (err) {
            throw new HttpError(400, (err as Error).message);
          }
        }

        default:
          return notFound(res);
      }
    } catch (err) {
      if (err instanceof HttpError) return send(res, err.status, { error: "bad_request", message: err.message });
      console.error(err);
      return send(res, 500, { error: "internal", message: String((err as Error)?.message ?? err) });
    }
  });
}
