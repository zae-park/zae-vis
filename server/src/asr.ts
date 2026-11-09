// Shared ASR sessions for chat voice (live) and meeting recordings (meeting).
// Whisper has no native stream API: we chunk PCM with an energy VAD and re-decode on a warm daemon.

import { randomBytes } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";

export type AsrMode = "live" | "meeting";
export type AsrPriority = "high" | "low";

export type AsrEvent = {
  type: "partial" | "final";
  text: string;
  at: string;
  t0?: number;
  t1?: number;
};

export type AsrTranscribe = (
  wav: string,
  opts?: { language?: string; beamSize?: number; vadFilter?: boolean; priority?: AsrPriority },
) => Promise<string>;

export type AsrPolicy = {
  emitPartial: boolean;
  partialEveryMs: number;
  beamPartial: number;
  beamFinal: number;
  silenceMs: number;
  maxSpeechMs: number;
  overlapMs: number;
  maxDurationMs: number;
  /** RMS of int16 samples / 32768; above → speech. */
  speechRms: number;
};

export const POLICY: Record<AsrMode, AsrPolicy> = {
  live: {
    emitPartial: true,
    partialEveryMs: 350,
    beamPartial: 1,
    beamFinal: 5,
    silenceMs: 500,
    maxSpeechMs: 20_000,
    overlapMs: 2_000,
    maxDurationMs: 120_000,
    speechRms: 0.012,
  },
  meeting: {
    emitPartial: false,
    partialEveryMs: 800,
    beamPartial: 1,
    beamFinal: 5,
    silenceMs: 600,
    maxSpeechMs: 20_000,
    overlapMs: 2_000,
    maxDurationMs: 4 * 3600_000,
    speechRms: 0.012,
  },
};

const SAMPLE_RATE = 16_000;
const BYTES_PER_SAMPLE = 2;
const FRAME_SAMPLES = 480; // 30 ms
const FRAME_BYTES = FRAME_SAMPLES * BYTES_PER_SAMPLE;

export function frameRms(pcm: Buffer, offset = 0, samples = FRAME_SAMPLES): number {
  const n = Math.min(samples, Math.floor((pcm.length - offset) / BYTES_PER_SAMPLE));
  if (n <= 0) return 0;
  let sum = 0;
  for (let i = 0; i < n; i++) {
    const v = pcm.readInt16LE(offset + i * BYTES_PER_SAMPLE);
    sum += v * v;
  }
  return Math.sqrt(sum / n) / 32768;
}

export function pcmDurationMs(bytes: number): number {
  return (bytes / BYTES_PER_SAMPLE / SAMPLE_RATE) * 1000;
}

/** Minimal WAV header + PCM (16-bit mono). */
export function wavFromPcm(pcm: Buffer, sampleRate = SAMPLE_RATE): Buffer {
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}

export type ChunkerState = {
  pending: Buffer;
  /** Frame list for the current utterance — avoid Buffer.concat per frame. */
  speech: Buffer[];
  speechBytes: number;
  inSpeech: boolean;
  silenceMs: number;
  speechMs: number;
  tMs: number;
  speechStartMs: number;
};

export function createChunker(): ChunkerState {
  return { pending: Buffer.alloc(0), speech: [], speechBytes: 0, inSpeech: false, silenceMs: 0, speechMs: 0, tMs: 0, speechStartMs: 0 };
}

export function speechBytes(state: ChunkerState): number {
  return state.speechBytes;
}

function takeSpeech(state: ChunkerState): Buffer {
  const pcm = Buffer.concat(state.speech, state.speechBytes);
  state.speech = [];
  state.speechBytes = 0;
  return pcm;
}

function appendFrame(state: ChunkerState, frame: Buffer): void {
  // Caller must pass an owned copy (chunkerPush copies each frame).
  state.speech.push(frame);
  state.speechBytes += frame.length;
}

function keepOverlap(state: ChunkerState, keepBytes: number): void {
  if (keepBytes <= 0 || state.speechBytes <= keepBytes) return;
  const all = Buffer.concat(state.speech, state.speechBytes);
  const tail = Buffer.from(all.subarray(all.length - keepBytes));
  // Keep as whole frames when possible so speech[] stays a frame list.
  const frames: Buffer[] = [];
  for (let off = 0; off + FRAME_BYTES <= tail.length; off += FRAME_BYTES) {
    frames.push(Buffer.from(tail.subarray(off, off + FRAME_BYTES)));
  }
  const rem = tail.length % FRAME_BYTES;
  if (rem) frames.push(Buffer.from(tail.subarray(tail.length - rem)));
  state.speech = frames.length ? frames : [tail];
  state.speechBytes = tail.length;
}

/** Worklog-relative path for a meeting draft transcript (whisperX overwrites the same stem). */
export function meetingDraftRelPath(name: string | undefined, id: string): string {
  const stem = (name ? basename(name).replace(/\.[^.]+$/, "") : `draft-${id}`).slice(0, 80);
  // Always `/` — worklog paths are POSIX-style on every OS.
  return `inbox/transcripts/${stem}.md`;
}

export function meetingDraftBody(stem: string, text: string): string {
  return [`# ${stem}`, "", "(zaevis 실시간 초안 — 고품질 전사가 끝나면 이 파일을 덮어씁니다)", "", text.trim(), ""].join("\n");
}

export type ChunkerTick =
  | { kind: "none" }
  | { kind: "speech"; pcm: Buffer; t0: number; t1: number; forceWindow: boolean }
  | { kind: "end"; pcm: Buffer; t0: number; t1: number };

export function chunkerPush(state: ChunkerState, pcm: Buffer, policy: AsrPolicy): ChunkerTick {
  state.pending = state.pending.length ? Buffer.concat([state.pending, pcm]) : Buffer.from(pcm);
  let action: ChunkerTick = { kind: "none" };
  while (state.pending.length >= FRAME_BYTES) {
    // Copy the frame — pending may be a large concat buffer we shrink via subarray.
    const frame = Buffer.from(state.pending.subarray(0, FRAME_BYTES));
    state.pending = state.pending.subarray(FRAME_BYTES);
    const rms = frameRms(frame);
    const frameMs = (FRAME_SAMPLES / SAMPLE_RATE) * 1000;
    const speaking = rms >= policy.speechRms;
    if (speaking) {
      if (!state.inSpeech) {
        state.inSpeech = true;
        state.speech = [];
        state.speechBytes = 0;
        state.speechMs = 0;
        state.silenceMs = 0;
        state.speechStartMs = state.tMs;
      }
      appendFrame(state, frame);
      state.speechMs += frameMs;
      state.silenceMs = 0;
      if (state.speechMs >= policy.maxSpeechMs) {
        const keep = Math.floor((policy.overlapMs / 1000) * SAMPLE_RATE) * BYTES_PER_SAMPLE;
        const all = Buffer.concat(state.speech, state.speechBytes);
        const cut = all.length > keep ? Buffer.from(all.subarray(0, all.length - keep)) : Buffer.from(all);
        const t0 = state.speechStartMs;
        const t1 = state.tMs + frameMs;
        action = { kind: "speech", pcm: cut, t0, t1, forceWindow: true };
        keepOverlap(state, keep);
        state.speechMs = pcmDurationMs(state.speechBytes);
        state.speechStartMs = t1 - state.speechMs;
      }
    } else if (state.inSpeech) {
      state.silenceMs += frameMs;
      appendFrame(state, frame);
      state.speechMs += frameMs;
      if (state.silenceMs >= policy.silenceMs) {
        const t0 = state.speechStartMs;
        const t1 = state.tMs + frameMs;
        action = { kind: "end", pcm: takeSpeech(state), t0, t1 };
        state.inSpeech = false;
        state.speechMs = 0;
        state.silenceMs = 0;
      }
    }
    state.tMs += frameMs;
    if (action.kind !== "none") break;
  }
  // Drop the large underlying ArrayBuffer when only a short leftover remains.
  if (state.pending.length === 0) state.pending = Buffer.alloc(0);
  else if (state.pending.byteOffset > 0 || state.pending.buffer.byteLength > state.pending.length + FRAME_BYTES) {
    state.pending = Buffer.from(state.pending);
  }
  return action;
}

export function chunkerFlush(state: ChunkerState): ChunkerTick {
  if (!state.inSpeech || state.speechBytes < FRAME_BYTES) {
    state.inSpeech = false;
    state.speech = [];
    state.speechBytes = 0;
    return { kind: "none" };
  }
  const t0 = state.speechStartMs;
  const t1 = state.tMs;
  const pcm = takeSpeech(state);
  state.inSpeech = false;
  state.speechMs = 0;
  state.silenceMs = 0;
  return { kind: "end", pcm, t0, t1 };
}

type QueuedWork<T> = {
  priority: AsrPriority;
  run: () => Promise<T>;
  resolve: (v: T) => void;
  reject: (e: unknown) => void;
  /** When true, waiting work resolves immediately without running (session cancel). */
  skip?: () => boolean;
};

/** Shared decode scheduler: high (finals) jump ahead of waiting lows (partials). */
export class DecodeQueue {
  private waiting: QueuedWork<unknown>[] = [];
  private active = 0;

  runQueued<T>(priority: AsrPriority, run: () => Promise<T>, skip?: () => boolean): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      this.waiting.push({
        priority,
        run: run as () => Promise<unknown>,
        resolve: resolve as (v: unknown) => void,
        reject,
        skip,
      });
      this.kick();
    });
  }

  /** Drop cancelled waiters (call after setting aborted so cancel does not wait on other sessions). */
  flushSkipped(): void {
    this.dropSkipped();
  }

  private dropSkipped(): void {
    if (!this.waiting.length) return;
    const keep: QueuedWork<unknown>[] = [];
    for (const w of this.waiting) {
      if (w.skip?.()) (w.resolve as (v: unknown) => void)(undefined);
      else keep.push(w);
    }
    this.waiting = keep;
  }

  private kick(): void {
    this.dropSkipped();
    if (this.active > 0) return;
    if (!this.waiting.length) return;
    // Prefer high over low among waiting items (stable among equals).
    let idx = 0;
    for (let i = 1; i < this.waiting.length; i++) {
      if (this.waiting[i]!.priority === "high" && this.waiting[idx]!.priority === "low") idx = i;
    }
    const next = this.waiting.splice(idx, 1)[0]!;
    if (next.skip?.()) {
      (next.resolve as (v: unknown) => void)(undefined);
      this.kick();
      return;
    }
    this.active = 1;
    next
      .run()
      .then(next.resolve, next.reject)
      .finally(() => {
        this.active = 0;
        this.kick();
      });
  }
}

export class AsrSession {
  readonly id: string;
  readonly mode: AsrMode;
  readonly policy: AsrPolicy;
  readonly language?: string;
  /** Optional recording file stem for meeting draft transcripts. */
  readonly name?: string;
  readonly createdAt = Date.now();
  private chunker = createChunker();
  private events: AsrEvent[] = [];
  private finals: string[] = [];
  private partialText = "";
  private lastPartialAt = 0;
  private closed = false;
  private aborted = false;
  private readonly transcribe: AsrTranscribe;
  private readonly queue: DecodeQueue;
  private tmpRoot: string;
  private inflight = 0;
  touchedAt = Date.now();

  private constructor(opts: {
    mode: AsrMode;
    language?: string;
    name?: string;
    transcribe: AsrTranscribe;
    queue: DecodeQueue;
    tmpRoot: string;
    policy?: AsrPolicy;
  }) {
    this.id = randomBytes(8).toString("hex");
    this.mode = opts.mode;
    this.language = opts.language;
    this.name = opts.name;
    this.policy = opts.policy ?? POLICY[opts.mode];
    this.transcribe = opts.transcribe;
    this.queue = opts.queue;
    this.tmpRoot = opts.tmpRoot;
  }

  static async open(opts: {
    mode: AsrMode;
    language?: string;
    name?: string;
    transcribe: AsrTranscribe;
    queue: DecodeQueue;
  }): Promise<AsrSession> {
    const tmpRoot = await mkdtemp(join(tmpdir(), "zaevis-asr-"));
    return new AsrSession({ ...opts, tmpRoot });
  }

  get text(): string {
    return this.finals.join(" ").replace(/\s+/g, " ").trim();
  }

  get partial(): string {
    return this.partialText;
  }

  get closedNow(): boolean {
    return this.closed;
  }

  takeEvents(from = 0): AsrEvent[] {
    return this.events.slice(from);
  }

  async pushAudio(pcm: Buffer): Promise<{ events: AsrEvent[]; partial: string; text: string }> {
    if (this.closed || this.aborted) throw new Error("세션이 이미 끝났습니다");
    this.touchedAt = Date.now();
    if (this.chunker.tMs + pcmDurationMs(pcm.length) > this.policy.maxDurationMs) {
      throw new Error("녹음이 너무 깁니다");
    }
    const before = this.events.length;
    let guard = 0;
    let rest = pcm;
    while (guard++ < 10_000) {
      const tick = chunkerPush(this.chunker, rest, this.policy);
      rest = Buffer.alloc(0);
      if (tick.kind === "none") break;
      if (tick.kind === "end" || (tick.kind === "speech" && tick.forceWindow)) {
        await this.decodeFinal(tick.pcm, tick.t0, tick.t1);
      }
    }
    if (this.policy.emitPartial && this.chunker.inSpeech && this.chunker.speechBytes >= FRAME_BYTES) {
      const now = Date.now();
      if (now - this.lastPartialAt >= this.policy.partialEveryMs) {
        this.lastPartialAt = now;
        await this.decodePartial(Buffer.concat(this.chunker.speech, this.chunker.speechBytes));
      }
    }
    return { events: this.takeEvents(before), partial: this.partialText, text: this.text };
  }

  async stop(): Promise<{ events: AsrEvent[]; partial: string; text: string }> {
    if (this.closed) return { events: [], partial: this.partialText, text: this.text };
    this.touchedAt = Date.now();
    const before = this.events.length;
    const tick = chunkerFlush(this.chunker);
    if (tick.kind === "end") await this.decodeFinal(tick.pcm, tick.t0, tick.t1);
    this.partialText = "";
    this.closed = true;
    await this.waitInflight();
    await this.cleanup();
    return { events: this.takeEvents(before), partial: "", text: this.text };
  }

  async cancel(): Promise<void> {
    this.aborted = true;
    this.closed = true;
    // Release waiters blocked behind other sessions' decodes before waiting on our inflight.
    this.queue?.flushSkipped();
    await this.waitInflight();
    await this.cleanup();
  }

  private async waitInflight(): Promise<void> {
    for (let i = 0; i < 200 && this.inflight > 0; i++) await new Promise((r) => setTimeout(r, 10));
  }

  private async cleanup(): Promise<void> {
    try {
      await rm(this.tmpRoot, { recursive: true, force: true });
    } catch {}
  }

  private async decodeFinal(pcm: Buffer, t0: number, t1: number): Promise<void> {
    if (pcm.length < FRAME_BYTES * 2 || this.aborted) return;
    this.inflight++;
    try {
      await this.queue.runQueued(
        "high",
        async () => {
          if (this.aborted) return;
          const text = await this.runDecode(pcm, this.policy.beamFinal, true, "high");
          if (this.aborted || !text) return;
          this.finals.push(text);
          this.partialText = "";
          this.events.push({ type: "final", text, at: new Date().toISOString(), t0, t1 });
        },
        () => this.aborted,
      );
    } finally {
      this.inflight--;
    }
  }

  private async decodePartial(pcm: Buffer): Promise<void> {
    if (this.aborted) return;
    this.inflight++;
    try {
      await this.queue.runQueued(
        "low",
        async () => {
          if (this.aborted || this.closed || !this.chunker.inSpeech) return;
          const text = await this.runDecode(pcm, this.policy.beamPartial, false, "low");
          if (this.aborted || text === this.partialText) return;
          this.partialText = text;
          this.events.push({ type: "partial", text, at: new Date().toISOString() });
        },
        () => this.aborted,
      );
    } finally {
      this.inflight--;
    }
  }

  private async runDecode(pcm: Buffer, beamSize: number, vadFilter: boolean, priority: AsrPriority): Promise<string> {
    if (this.aborted) return "";
    const file = join(this.tmpRoot, `c-${Date.now()}-${randomBytes(3).toString("hex")}.wav`);
    try {
      await writeFile(file, wavFromPcm(pcm));
      if (this.aborted) return "";
      return (await this.transcribe(file, { language: this.language, beamSize, vadFilter, priority })).trim();
    } catch {
      return "";
    } finally {
      await rm(file, { force: true }).catch(() => {});
    }
  }
}

export class AsrHub {
  private sessions = new Map<string, AsrSession>();
  private readonly transcribe: AsrTranscribe;
  private readonly idleMs: number;
  private readonly maxSessions: number;
  private readonly queue = new DecodeQueue();
  private sweeper: NodeJS.Timeout | null = null;

  constructor(opts: { transcribe: AsrTranscribe; idleMs?: number; maxSessions?: number }) {
    this.transcribe = opts.transcribe;
    this.idleMs = opts.idleMs ?? 120_000;
    this.maxSessions = opts.maxSessions ?? 2;
  }

  /** Exposed for unit tests of the priority scheduler. */
  runQueued<T>(priority: AsrPriority, run: () => Promise<T>, skip?: () => boolean): Promise<T> {
    return this.queue.runQueued(priority, run, skip);
  }

  async create(mode: AsrMode, language?: string, name?: string): Promise<AsrSession> {
    this.sweep();
    if (this.sessions.size >= this.maxSessions) {
      const oldest = [...this.sessions.values()].sort((a, b) => a.touchedAt - b.touchedAt)[0];
      if (oldest) {
        await oldest.cancel();
        this.sessions.delete(oldest.id);
      }
    }
    const s = await AsrSession.open({ mode, language, name, transcribe: this.transcribe, queue: this.queue });
    this.sessions.set(s.id, s);
    this.ensureSweep();
    return s;
  }

  get(id: string): AsrSession | undefined {
    const s = this.sessions.get(id);
    if (s) s.touchedAt = Date.now();
    return s;
  }

  async remove(id: string): Promise<boolean> {
    const s = this.sessions.get(id);
    if (!s) return false;
    await s.cancel();
    this.sessions.delete(id);
    return true;
  }

  forget(id: string): void {
    this.sessions.delete(id);
  }

  private sweep(): void {
    const now = Date.now();
    for (const [id, s] of this.sessions) {
      if (s.closedNow || now - s.touchedAt > this.idleMs) {
        void s.cancel();
        this.sessions.delete(id);
      }
    }
  }

  private ensureSweep(): void {
    if (this.sweeper) return;
    this.sweeper = setInterval(() => this.sweep(), 30_000);
    this.sweeper.unref();
  }

  stop(): void {
    if (this.sweeper) clearInterval(this.sweeper);
    this.sweeper = null;
    for (const s of this.sessions.values()) void s.cancel();
    this.sessions.clear();
  }
}
