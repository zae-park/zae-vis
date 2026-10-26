// Local semantic search: keeps a `minsync serve` embedding daemon running so AutoRAG Lite can embed
// chunks and queries on this machine (Qwen3-Embedding-0.6B, no account or API key).
//
// AutoRAG finds the daemon by itself: `minsync serve` writes host/port files under
// ~/.cache/minsync/serve/<model instance>/ and answers GET /health with the model id. A second
// `minsync serve` for the same model adopts the running one (event "adopted") and exits 0.
// The first start downloads the model (~1.1GB) into ~/.cache/minsync/models.

import { spawn, type ChildProcess } from "node:child_process";
import { existsSync } from "node:fs";
import { delimiter, join } from "node:path";

export type EmbeddingState = "off" | "starting" | "ready" | "failed";

export type EmbeddingStatus = {
  enabled: boolean;
  state: EmbeddingState;
  /** `minsync` binary found on PATH (bundled in the app). */
  available: boolean;
  url?: string;
  model?: string;
  device?: string;
  pid?: number;
  /** True when the daemon was started by someone else and merely adopted. */
  external?: boolean;
  startedAt?: string;
  error?: string;
};

type ServeEvent = { event?: string; url?: string; model_id?: string; device?: string; pid?: number; status?: string };

export function findMinsync(env: NodeJS.ProcessEnv = process.env): string | null {
  for (const dir of (env.PATH ?? "").split(delimiter)) {
    if (!dir) continue;
    const p = join(dir, process.platform === "win32" ? "minsync.exe" : "minsync");
    if (existsSync(p)) return p;
  }
  return null;
}

export type EmbeddingDaemonOptions = {
  binary?: string | null;
  /** Seconds idle before the daemon exits by itself; 0 = until stopped (the server's choice). */
  idleTimeout?: number;
  /** Let the daemon outlive this process (used by the daily job). */
  detached?: boolean;
  env?: NodeJS.ProcessEnv;
  log?: (msg: string) => void;
  healthTimeoutMs?: number;
};

export class EmbeddingDaemon {
  private readonly binary: string | null;
  private readonly opts: EmbeddingDaemonOptions;
  private child: ChildProcess | null = null;
  private status: EmbeddingStatus;
  private starting: Promise<EmbeddingStatus> | null = null;

  constructor(opts: EmbeddingDaemonOptions = {}) {
    this.opts = opts;
    this.binary = opts.binary === undefined ? findMinsync(opts.env) : opts.binary;
    this.status = { enabled: false, state: "off", available: this.binary !== null };
  }

  get current(): EmbeddingStatus {
    return { ...this.status };
  }

  /** Starts the daemon (or adopts a running one). Resolves once it answers, or with state "failed". */
  start(): Promise<EmbeddingStatus> {
    if (this.status.state === "ready" || this.status.state === "starting") return this.starting ?? Promise.resolve(this.current);
    if (!this.binary) {
      this.status = { enabled: true, state: "failed", available: false, error: "minsync 실행 파일을 찾지 못했습니다 (앱 설치본에 포함되어 있어야 합니다)." };
      return Promise.resolve(this.current);
    }
    this.status = { enabled: true, state: "starting", available: true, startedAt: new Date().toISOString() };
    this.starting = this.spawnDaemon().finally(() => {
      this.starting = null;
    });
    return this.starting;
  }

  private spawnDaemon(): Promise<EmbeddingStatus> {
    const args = ["serve", "--format", "json", "--quiet", "--idle-timeout", String(this.opts.idleTimeout ?? 0)];
    const detached = this.opts.detached === true && process.platform !== "win32";
    const child = spawn(this.binary!, args, { env: this.opts.env ?? process.env, detached, stdio: ["ignore", "pipe", "pipe"] });
    this.child = child;
    let stderr = "";
    let buffer = "";
    let settled = false;

    return new Promise<EmbeddingStatus>((resolve) => {
      const finish = () => {
        if (settled) return;
        settled = true;
        resolve(this.current);
      };
      child.stderr?.setEncoding("utf8");
      child.stderr?.on("data", (chunk: string) => {
        stderr = (stderr + chunk).slice(-2000);
      });
      child.stdout?.setEncoding("utf8");
      child.stdout?.on("data", (chunk: string) => {
        buffer += chunk;
        let nl: number;
        while ((nl = buffer.indexOf("\n")) >= 0) {
          const line = buffer.slice(0, nl).trim();
          buffer = buffer.slice(nl + 1);
          if (!line.startsWith("{")) continue;
          let ev: ServeEvent;
          try {
            ev = JSON.parse(line) as ServeEvent;
          } catch {
            continue;
          }
          if (ev.event === "serving" || ev.event === "adopted") {
            this.status = {
              enabled: true,
              state: "ready",
              available: true,
              url: ev.url,
              model: ev.model_id,
              device: ev.device,
              pid: ev.pid,
              external: ev.event === "adopted",
              startedAt: this.status.startedAt,
            };
            this.opts.log?.(`[embedding] ${ev.event}: ${ev.model_id} on ${ev.device} at ${ev.url}`);
            if (ev.event === "adopted" || detached) {
              // not our process to keep: the adopted daemon, or one left to outlive us
              child.stdout?.destroy();
              child.stderr?.destroy();
              child.unref();
              this.child = null;
            }
            finish();
          }
        }
      });
      child.on("error", (err) => {
        this.status = { enabled: true, state: "failed", available: true, error: `minsync serve 실행 실패: ${err.message}` };
        this.child = null;
        finish();
      });
      child.on("exit", (code, signal) => {
        if (this.child !== child) return; // adopted / detached: its exit is not ours to judge
        this.child = null;
        if (this.status.state === "ready" && !this.status.external) {
          if (code === 0 || signal === "SIGTERM") this.status = { enabled: this.status.enabled, state: "off", available: true };
          else this.status = { enabled: true, state: "failed", available: true, error: `minsync serve 종료 (code ${code ?? signal}): ${stderr.trim().split("\n").pop() ?? ""}` };
        } else if (this.status.state === "starting") {
          this.status = { enabled: true, state: "failed", available: true, error: `minsync serve 가 준비되기 전에 끝났습니다 (code ${code ?? signal}): ${stderr.trim().split("\n").pop() ?? "(출력 없음)"}` };
        }
        finish();
      });
    });
  }

  /** Re-checks a ready daemon over HTTP; marks it off when it has gone away. */
  async health(): Promise<EmbeddingStatus> {
    if (this.status.state !== "ready" || !this.status.url) return this.current;
    try {
      const res = await fetch(`${this.status.url}/health`, { signal: AbortSignal.timeout(this.opts.healthTimeoutMs ?? 2000) });
      const body = (await res.json()) as ServeEvent;
      if (!res.ok || body.status !== "ok") throw new Error(`health ${res.status}`);
    } catch {
      if (!this.child) this.status = { enabled: this.status.enabled, state: "off", available: true };
    }
    return this.current;
  }

  /**
   * Stops the daemon. zaevis owns the daemon's lifecycle on this machine, so an adopted one (left by a
   * crashed server, or started by the daily job) is terminated by pid as well.
   */
  async stop(): Promise<EmbeddingStatus> {
    const child = this.child;
    const { pid, url, state } = this.status;
    this.child = null;
    this.status = { enabled: false, state: "off", available: this.binary !== null };
    if (!child && state === "ready" && pid) {
      try {
        process.kill(pid, "SIGTERM");
      } catch {
        return this.current; // already gone
      }
      const deadline = Date.now() + 5000;
      while (Date.now() < deadline) {
        try {
          await fetch(`${url}/health`, { signal: AbortSignal.timeout(300) });
        } catch {
          break;
        }
        await new Promise((r) => setTimeout(r, 150));
      }
      return this.current;
    }
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise<void>((resolve) => {
        const t = setTimeout(() => {
          child.kill("SIGKILL");
          resolve();
        }, 5000);
        child.once("exit", () => {
          clearTimeout(t);
          resolve();
        });
      });
    }
    return this.current;
  }
}
