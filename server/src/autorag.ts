// Talks to AutoRAG Lite through its stdio MCP server (`autorag-mcp`).
// Lite mode needs no chat model or API key: search is BM25 + local MinSync vectors.

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describeHit, type HitContext } from "./context.ts";

export type SearchHit = {
  number: number;
  title: string;
  path: string;      // path relative to the worklog root when possible
  /** The best-matching passage of the chunk (see context.ts). */
  snippet: string;
  score: number | null;
  /** Relative score well below the top hit: shown dimmed as a weak match. */
  weak: boolean;
  context: HitContext;
};

export type SearchResponse = {
  ok: boolean;
  query: string;
  hits: SearchHit[];
  error?: { code: string; message: string };
};

/** AutoRAG refresh phases (`autorag.refresh` → `methods`). */
export type RefreshPhase = "parsed" | "minsync" | "datasources" | "jikji" | "everything" | "fsearch";

/** What the HTTP layer needs. A fake implements this in tests. */
export interface SearchBackend {
  status(): Promise<unknown>;
  /** `phases` limits the run (e.g. `["datasources"]` syncs only the external connections). */
  refresh(force?: boolean, phases?: RefreshPhase[]): Promise<unknown>;
  /** `passageChars` widens the passage of each hit (the "ask" flow feeds longer excerpts to a model). */
  search(query: string, topK: number, passageChars?: number): Promise<SearchResponse>;
  /** External connections AutoRAG has loaded (`autorag.datasources.list`); null when it cannot answer. */
  datasources?(): Promise<Array<Record<string, unknown>> | null>;
  /** Drops the child so the next call reads the config file again. */
  restart?(): Promise<void>;
  close(): Promise<void>;
}

type ToolResult = { structuredContent?: unknown; content?: Array<{ type: string; text?: string }>; isError?: boolean };

function payload(result: ToolResult): unknown {
  if (result.structuredContent !== undefined) return result.structuredContent;
  const text = result.content?.find((c) => c.type === "text")?.text;
  if (text === undefined) return null;
  try {
    return JSON.parse(text);
  } catch {
    return { text };
  }
}

// AutoRAG scales scores so the top hit is 1; anything this far below it is noise more often than not.
const WEAK_SCORE = 0.2;
const str = (v: unknown): string => (typeof v === "string" ? v : "");
const clip = (s: string, n: number): string => (s.length > n ? s.slice(0, n).trimEnd() + "…" : s);
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

/** Strip AutoRAG's virtual root ("/worklog/…" for a search path named worklog) and absolute roots. */
export function displayPath(raw: string, roots: string[]): string {
  for (const r of roots) {
    if (raw.startsWith(r + "/")) return raw.slice(r.length + 1);
    if (raw.startsWith("/private" + r + "/")) return raw.slice("/private".length + r.length + 1); // macOS /tmp realpath
  }
  return raw.replace(/^\/[^/]+\//, "");
}

/**
 * Normalises an `autorag.search` payload. The Lite result shape is not a published contract,
 * so this accepts the common field names and keeps going when some are missing.
 */
export function normalizeSearch(query: string, data: unknown, roots: string[] = [], passageChars = 420): SearchResponse {
  const d = (data ?? {}) as Record<string, unknown>;
  if (d.ok === false) {
    return {
      ok: false,
      query,
      hits: [],
      error: { code: str(d.errorCode) || "error", message: str(d.message) || "AutoRAG returned an error" },
    };
  }
  const list = (Array.isArray(d.results) ? d.results : Array.isArray(d.hits) ? d.hits : Array.isArray(d.chunks) ? d.chunks : []) as Array<Record<string, unknown>>;
  const hits = list.map((r, i): SearchHit => {
    const src = (r.source && typeof r.source === "object" ? r.source : {}) as Record<string, unknown>;
    const meta = (r.metadata && typeof r.metadata === "object" ? r.metadata : {}) as Record<string, unknown>;
    const rawPath = str(r.path) || str(r.virtualPath) || str(r.sourcePath) || str(src.path) || str(src.virtualPath) || str(r.source) || str(r.file);
    // An external datasource hit keeps its opaque source ("/obsidian/default/노트.md") so the kind stays visible.
    const datasourceId = str(meta.datasourceId) || null;
    const path = datasourceId ? rawPath : displayPath(rawPath, roots);
    const content = (str(r.snippet) || str(r.summary) || str(r.text) || str(r.content) || str(r.chunk)).trim();
    const context = describeHit(path, content, query, passageChars, datasourceId ? { datasourceId, file: str(meta.path) || null, title: str(meta.title) || null } : undefined);
    const score = num(r.score) ?? num(r.relevance);
    return {
      number: num(r.number) ?? num(r.rank) ?? i + 1,
      title: str(r.title) || str(src.title) || str(meta.title) || path.split("/").pop() || `#${i + 1}`,
      path,
      snippet: context.passage || clip(content, 600),
      score,
      weak: score !== null && score < WEAK_SCORE,
      context,
    };
  });
  return { ok: true, query, hits };
}

function friendly(err: unknown): string {
  const msg = String((err as Error)?.message ?? err);
  return /Connection closed|ENOENT|spawn/.test(msg)
    ? `AutoRAG MCP 서버를 실행하지 못했습니다 (${msg}). 'zaevis logs'에서 원인을 확인하세요.`
    : msg;
}

function defaultMcpBin(): string {
  const here = dirname(fileURLToPath(import.meta.url));
  const local = join(here, "..", "node_modules", ".bin", "autorag-mcp");
  return existsSync(local) ? local : "autorag-mcp";
}

export class AutoRAGMcp implements SearchBackend {
  private client: Client | null = null;
  private connecting: Promise<Client> | null = null;
  private readonly configPath: string;
  private readonly roots: string[];
  private readonly bin: string;
  private readonly extraEnv: () => Record<string, string>;

  constructor(opts: { configPath: string; roots: string[]; bin?: string; env?: () => Record<string, string> }) {
    this.configPath = opts.configPath;
    this.roots = opts.roots;
    this.bin = opts.bin ?? defaultMcpBin();
    this.extraEnv = opts.env ?? (() => ({}));
  }

  /** Drops the child so the next call starts a fresh one (new config file contents, new env). */
  async restart(): Promise<void> {
    await this.close();
  }

  private async connect(): Promise<Client> {
    if (this.client) return this.client;
    if (!this.connecting) {
      this.connecting = (async () => {
        const transport = new StdioClientTransport({
          command: this.bin,
          env: { ...(process.env as Record<string, string>), ...this.extraEnv(), AUTORAG_CONFIG: this.configPath },
          stderr: "inherit",
        });
        const client = new Client({ name: "zaevis", version: "0.1.0" });
        transport.onclose = () => {
          this.client = null;
        };
        await client.connect(transport);
        this.client = client;
        return client;
      })().finally(() => {
        this.connecting = null;
      });
    }
    return this.connecting;
  }

  private async call(name: string, args: Record<string, unknown>, timeoutMs = 120_000): Promise<unknown> {
    const client = await this.connect();
    const result = (await client.callTool({ name, arguments: args }, undefined, { timeout: timeoutMs })) as ToolResult;
    return payload(result);
  }

  private notConfigured(): string | null {
    return existsSync(this.configPath)
      ? null
      : `AutoRAG가 설정되지 않았습니다 (${this.configPath} 없음). 'zaevis setup'을 --no-autorag 없이 실행하세요.`;
  }

  async status(): Promise<unknown> {
    const missing = this.notConfigured();
    if (missing) return { state: "not-configured", stale: false, lastError: missing, diagnostics: [] };
    try {
      return await this.call("autorag.status", {});
    } catch (err) {
      return { state: "unavailable", stale: false, lastError: friendly(err), diagnostics: [] };
    }
  }

  async refresh(force = false, phases?: RefreshPhase[]): Promise<unknown> {
    const missing = this.notConfigured();
    if (missing) throw new Error(missing);
    // First refresh builds embeddings and can take minutes; a datasource sync has a 30-minute budget per connector.
    return this.call("autorag.refresh", { ...(force ? { force: true } : {}), ...(phases?.length ? { methods: phases } : {}) }, 30 * 60_000);
  }

  async datasources(): Promise<Array<Record<string, unknown>> | null> {
    if (this.notConfigured()) return null;
    try {
      const d = (await this.call("autorag.datasources.list", {}, 30_000)) as { datasources?: unknown };
      return Array.isArray(d?.datasources) ? (d.datasources as Array<Record<string, unknown>>) : null;
    } catch {
      return null;
    }
  }

  async search(query: string, topK: number, passageChars?: number): Promise<SearchResponse> {
    const missing = this.notConfigured();
    if (missing) return { ok: false, query, hits: [], error: { code: "not-configured", message: missing } };
    try {
      return normalizeSearch(query, await this.call("autorag.search", { query, topK }), this.roots, passageChars);
    } catch (err) {
      return { ok: false, query, hits: [], error: { code: "search-failed", message: friendly(err) } };
    }
  }

  async close(): Promise<void> {
    await this.client?.close();
    this.client = null;
  }
}
