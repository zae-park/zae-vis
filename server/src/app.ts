// HTTP API for the Flutter front-end. Binds to loopback only; see main.ts.

import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { createWriteStream } from "node:fs";
import { mkdir, readFile, rm, stat } from "node:fs/promises";
import { basename, extname, join, normalize, sep } from "node:path";
import type { SearchBackend } from "./autorag.ts";
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
    update(patch: { dailyAt?: string; indexOnInject?: boolean; localEmbedding?: boolean }): Promise<Record<string, unknown>>;
    indexOnInject(): boolean;
  };
  /** Local embedding daemon (semantic search); absent when minsync is not managed here. */
  embedding?: {
    status(): Promise<Record<string, unknown>>;
    /** Returns true when the daemon just became ready (caller re-indexes so vectors get built). */
    set(enabled: boolean): Promise<boolean>;
  };
  audio?: {
    dir(): string;
    enqueue(file: string): void;
    jobs(): unknown[];
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

  function startRefresh(force: boolean): void {
    if (refreshing) return;
    refreshing = search
      .refresh(force)
      .then(() => {
        lastRefresh = { finishedAt: new Date().toISOString(), ok: true };
      })
      .catch((err: unknown) => {
        lastRefresh = { finishedAt: new Date().toISOString(), ok: false, error: String((err as Error)?.message ?? err) };
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

        case "GET /index":
          return send(res, 200, {
            refreshing: refreshing !== null,
            lastRefresh,
            autorag: await search.status(),
            ...(opts.embedding ? { embedding: await opts.embedding.status() } : {}),
          });

        case "POST /index": {
          const body = await readJson(req);
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

        case "PUT /settings": {
          if (!opts.settings) return notFound(res);
          const b = await readJson(req);
          const patch: { dailyAt?: string; indexOnInject?: boolean; localEmbedding?: boolean } = {};
          if (typeof b.dailyAt === "string") patch.dailyAt = b.dailyAt;
          if (typeof b.indexOnInject === "boolean") patch.indexOnInject = b.indexOnInject;
          if (typeof b.localEmbedding === "boolean") patch.localEmbedding = b.localEmbedding;
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
