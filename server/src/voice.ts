// Speech → text for the chat's microphone (POST /api/voice). Uses the whisperX extension's own Python with
// faster-whisper, kept running by voice_daemon.py so a short command is text in ~3 s instead of ~14 s
// (measured on an M-series Mac: 6 s of Korean speech, large-v3-turbo int8). Nothing is saved: the audio is a
// temporary file that is deleted once read, and the text goes back to the chat only.

import { spawnBin } from "./spawnbin.ts";
import type { ChildProcess } from "node:child_process";
import { availableParallelism } from "node:os";
import { delimiter, dirname, join } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

/** Short bursts, so every core up to 8 (8 threads: ~3.1 s for 6 s of speech; 4 threads: ~4.9 s). */
export const VOICE_THREADS = Math.min(8, Math.max(1, availableParallelism()));
/** The model leaves memory (about 1.5 GB) after this long without a command. */
export const VOICE_IDLE_MS = 10 * 60_000;
const READY_TIMEOUT_MS = 120_000; // the first start may download the model
const RUN_TIMEOUT_MS = 60_000;

type Pending = { resolve: (text: string) => void; reject: (err: Error) => void; timer: NodeJS.Timeout };

export class VoiceTranscriber {
  private child: ChildProcess | null = null;
  private ready: Promise<void> | null = null;
  private pending = new Map<number, Pending>();
  private nextId = 1;
  private idle: NodeJS.Timeout | null = null;

  /** `script` replaces voice_daemon.py in tests; `idleMs` the idle time before the model is dropped. */
  private readonly opts: { python: () => string | null; model?: () => string; log?: (line: string) => void; script?: string; idleMs?: number };

  constructor(opts: { python: () => string | null; model?: () => string; log?: (line: string) => void; script?: string; idleMs?: number }) {
    this.opts = opts;
  }

  get running(): boolean {
    return this.child !== null;
  }

  /** Text of the speech in [wav] (language undefined: whisper detects it). Starts the daemon on first use. */
  async transcribe(wav: string, language?: string): Promise<string> {
    await this.start();
    const child = this.child;
    if (!child?.stdin) throw new Error("음성 인식기를 시작하지 못했습니다");
    this.touch();
    const id = this.nextId++;
    return new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error("음성 인식이 너무 오래 걸립니다"));
      }, RUN_TIMEOUT_MS);
      this.pending.set(id, { resolve, reject, timer });
      child.stdin!.write(JSON.stringify({ id, path: wav, language: language ?? null }) + "\n");
    });
  }

  stop(): void {
    if (this.idle) clearTimeout(this.idle);
    this.idle = null;
    const child = this.child;
    this.child = null;
    this.ready = null;
    try {
      child?.stdin?.end();
    } catch {}
    setTimeout(() => child?.kill(), 2000).unref();
  }

  private touch(): void {
    if (this.idle) clearTimeout(this.idle);
    this.idle = setTimeout(() => this.stop(), this.opts.idleMs ?? VOICE_IDLE_MS);
    this.idle.unref();
  }

  private start(): Promise<void> {
    if (this.ready) return this.ready;
    const python = this.opts.python();
    if (!python) return Promise.reject(new Error("음성으로 말하려면 whisperX가 필요합니다. 설정 → 녹음에서 설치하세요."));
    const script = this.opts.script ?? join(dirname(fileURLToPath(import.meta.url)), "voice_daemon.py");
    const model = this.opts.model?.() || "large-v3-turbo";
    this.ready = new Promise<void>((resolve, reject) => {
      const child = spawnBin(python, ["-I", script, model, String(VOICE_THREADS)], {
        // ffmpeg is linked next to the venv's python by `zaevis ext install whisperx`
        env: { ...process.env, PYTHONUNBUFFERED: "1", PATH: [dirname(python), process.env.PATH ?? ""].filter(Boolean).join(delimiter) },
        stdio: ["pipe", "pipe", "pipe"],
      });
      this.child = child;
      let err = "";
      const failStart = setTimeout(() => {
        reject(new Error("음성 인식기가 준비되지 않습니다"));
        this.stop();
      }, READY_TIMEOUT_MS);
      child.stderr?.on("data", (b: Buffer) => {
        err = (err + b.toString()).slice(-2000);
      });
      createInterface({ input: child.stdout! }).on("line", (line) => {
        let msg: { ready?: boolean; id?: number; text?: string; error?: string };
        try {
          msg = JSON.parse(line);
        } catch {
          return;
        }
        if (msg.ready) {
          clearTimeout(failStart);
          this.opts.log?.(`음성 인식기 준비 (${model}, ${VOICE_THREADS}스레드)`);
          resolve();
          return;
        }
        const p = msg.id === undefined ? undefined : this.pending.get(msg.id);
        if (!p) return;
        this.pending.delete(msg.id!);
        clearTimeout(p.timer);
        if (msg.error) p.reject(new Error(`음성 인식 실패: ${msg.error}`));
        else p.resolve(msg.text ?? "");
      });
      child.on("error", (e) => {
        clearTimeout(failStart);
        reject(e);
      });
      child.on("close", (code) => {
        clearTimeout(failStart);
        if (this.child === child) {
          this.child = null;
          this.ready = null;
        }
        const why = new Error(`음성 인식기가 끝났습니다 (${code ?? "신호"}): ${err.trim().split("\n").slice(-2).join(" ")}`);
        reject(why); // no-op once ready
        for (const [id, p] of this.pending) {
          clearTimeout(p.timer);
          p.reject(why);
          this.pending.delete(id);
        }
      });
    });
    this.ready.catch(() => {});
    return this.ready;
  }
}
