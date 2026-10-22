// HTTP API for the Flutter front-end. Binds to loopback only; see main.ts.

import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, sep } from "node:path";
import type { SearchBackend } from "./autorag.ts";
import type { Worklog } from "./worklog.ts";

export type AppOptions = {
  worklog: Worklog;
  search: SearchBackend;
  webDir?: string | null; // built Flutter web app (app/build/web), served at "/"
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

function send(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(body));
}

const notFound = (res: ServerResponse) => send(res, 404, { error: "not_found" });

async function readJson(req: IncomingMessage): Promise<Record<string, unknown>> {
  let body = "";
  for await (const chunk of req) {
    body += chunk;
    if (body.length > 64 * 1024) throw new Error("body too large");
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

  return createServer(async (req, res) => {
    const origin = req.headers.origin;
    if (origin && LOCAL_ORIGIN.test(origin)) {
      res.setHeader("access-control-allow-origin", origin);
      res.setHeader("vary", "origin");
      res.setHeader("access-control-allow-headers", "content-type");
      res.setHeader("access-control-allow-methods", "GET, POST, OPTIONS");
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
          return send(res, 200, { ok: true, worklog: worklog.root });

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
          return send(res, 200, { refreshing: refreshing !== null, lastRefresh, autorag: await search.status() });

        case "POST /index": {
          const body = await readJson(req);
          if (!refreshing) {
            refreshing = search
              .refresh(body.force === true)
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
          return send(res, 202, { refreshing: true });
        }

        default:
          return notFound(res);
      }
    } catch (err) {
      console.error(err);
      return send(res, 500, { error: "internal", message: String((err as Error)?.message ?? err) });
    }
  });
}
