// Audio → text with whisperX (optional extension, installed by `zaevis ext install whisperx`).
// Recognition runs first and the text is saved before anyone waits on speakers. CTranslate2 on
// this build has no GPU backend, so the one process uses every CPU core, skips the alignment
// model, and leaves pyannote for a later pass that rewrites the same file.

import { spawnBin } from "./spawnbin.ts";
import type { ChildProcess } from "node:child_process";
import { existsSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, readdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { availableParallelism, tmpdir } from "node:os";
import { basename, delimiter, dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { expandHome, stateDir } from "./config.ts";
import { diarizeDir, ensureDiarizer, formatSpeakerTurns } from "./diarize.ts";
import { tokenForDiarize } from "./hf.ts";
import { notify } from "./notify.ts";
import { redact } from "./redact.ts";
import { dayKey } from "./sources/types.ts";

export const AUDIO_EXT = new Set([".m4a", ".mp3", ".wav", ".aac", ".flac", ".ogg", ".opus", ".webm", ".mp4", ".mov", ".m4v"]);
export const TEXT_EXT = new Set([".txt", ".md", ".vtt", ".srt"]);

export type TranscribeOptions = {
  /** A language code; undefined lets whisper detect it (설정 → 녹음 → 전사 언어 "자동 감지"). */
  language?: string;
  model?: string;
  whisperxBin?: string;
  hfToken?: string;
  /** Label speakers after the text is saved (default on). Hugging Face pyannote when logged in, else sherpa-onnx. */
  speakers?: boolean;
  /** CPU use: "quiet" (default, 4 threads) or "fast" (every core). */
  speed?: TranscribeSpeed;
  /** A line whisperX printed. */
  onBeat?: (line: string) => void;
  /** Still inside this file, even when whisperX has not printed anything. */
  onTick?: () => void;
  /** Korean status and a 0–1 fraction. Fraction is null while a phase has not reported a percent yet. */
  onProgress?: (p: { line: string; fraction: number | null }) => void;
  /** Fired when a later speaker pass rewrites the transcript. The text is already saved by then. */
  onSpeakers?: (file: string) => void;
};

/** "quiet" keeps the fan down (4 threads), "fast" takes every core. */
export type TranscribeSpeed = "quiet" | "fast";

/** Threads in quiet mode. Measured on an M-series Mac: 4 threads took 1.4× as long as all 14 cores but
 * kept about 3 cores busy instead of 7 and used 40% less CPU time in total, with the same text. */
export const QUIET_THREADS = 4;

/** CPU threads for recognition (CTranslate2 here has no GPU device) and the speaker pass. */
export function transcribeThreads(speed: TranscribeSpeed = "quiet"): number {
  const all = Math.max(1, availableParallelism());
  return speed === "fast" ? all : Math.min(QUIET_THREADS, all);
}

/** Arguments for the fast pass: text first, no alignment model, no speaker labels. */
export function transcribeLaunchArgs(audio: string, outDir: string, opts: { model?: string; language?: string; threads?: number } = {}): string[] {
  return [
    audio,
    "--model", opts.model ?? "large-v3-turbo",
    ...(opts.language ? ["--language", opts.language] : []),
    "--compute_type", "int8",
    "--device", "cpu",
    "--threads", String(opts.threads ?? transcribeThreads()),
    "--vad_method", "silero",
    "--no_align",
    "--output_dir", outDir,
    "--output_format", "all",
    "--print_progress", "True",
    "--verbose", "False",
    "--log-level", "info",
  ];
}

/** What the app shows for one whisperX log line. Null means the line is chatter (a transcript sentence, a download bar). */
export type WhisperView = { label: string; fraction: number | null };

export function foldWhisperLine(state: WhisperView, raw: string): WhisperView | null {
  const line = raw.replace(/\u001b\[[0-9;]*[A-Za-z]/g, "").trim();
  if (!line) return null;
  const pct = /Progress:\s*([\d.]+)\s*%/.exec(line);
  if (pct) {
    const n = Number(pct[1]);
    if (!Number.isFinite(n)) return null;
    return { label: state.label, fraction: Math.min(1, Math.max(0, n / 100)) };
  }
  if (/Performing transcription/i.test(line)) return { label: "음성 인식", fraction: null };
  if (/Performing alignment/i.test(line)) return { label: "말 시간에 맞추는 중", fraction: null };
  if (/Performing diarization/i.test(line)) return { label: "말한 사람 구분 중", fraction: null };
  return null;
}

export function whisperStatusLine(state: WhisperView): string {
  return state.fraction == null ? state.label : `${state.label} ${Math.round(state.fraction * 100)}%`;
}

function textLines(chunk: string): string[] {
  return chunk
    .replace(/\u001b\[[0-9;]*[A-Za-z]/g, "")
    .replace(/\r/g, "\n")
    .split("\n")
    .map((s) => s.trim())
    .filter(Boolean);
}

export function whisperxBin(explicit?: string): string | null {
  const win = process.platform === "win32";
  const exe = win ? "whisperx.exe" : "whisperx";
  const candidates = [explicit, process.env.ZAEVIS_WHISPERX, join(stateDir(), "ext", "whisperx", win ? "Scripts" : "bin", exe)].filter(Boolean) as string[];
  for (const c of candidates) if (existsSync(expandHome(c))) return expandHome(c);
  for (const dir of (process.env.PATH ?? "").split(win ? ";" : ":")) if (dir && existsSync(join(dir, exe))) return join(dir, exe);
  return null;
}

/** "2026-10-21_회의.m4a" stays; "회의.m4a" recorded on 10-21 becomes "2026-10-21_회의". */
export async function datedStem(file: string): Promise<string> {
  const stem = basename(file, extname(file)).replace(/[^\p{L}\p{N}._ -]+/gu, "_").trim() || "audio";
  if (/^\d{4}-\d{2}-\d{2}/.test(stem)) return stem;
  return `${dayKey((await stat(file)).mtime)}_${stem}`;
}

/** Moves a file without needing delete permission on another volume (copy, then best-effort remove). */
export async function moveFile(src: string, dest: string): Promise<void> {
  await mkdir(join(dest, ".."), { recursive: true });
  try {
    await rename(src, dest);
  } catch {
    await copyFile(src, dest);
    await rm(src, { force: true }).catch(() => {});
  }
}

export function uniquePath(dir: string, stem: string, ext: string): string {
  let p = join(dir, stem + ext);
  for (let i = 2; existsSync(p); i++) p = join(dir, `${stem}_${i}${ext}`);
  return p;
}

/** Thrown when the user stops a transcription. The audio file stays where it was. */
export class TranscribeCancelled extends Error {
  constructor() {
    super("전사를 취소했습니다");
    this.name = "TranscribeCancelled";
  }
}

type ActiveRun = {
  cancelled: boolean;
  child: ChildProcess | null;
  kill(): void;
};

const active = new Map<string, ActiveRun>();

function trackRun(audio: string): ActiveRun {
  const slot: ActiveRun = {
    cancelled: false,
    child: null,
    kill() {
      this.cancelled = true;
      const child = this.child;
      const pid = child?.pid;
      if (pid && process.platform !== "win32") {
        try {
          process.kill(-pid, "SIGTERM");
          return;
        } catch {
          /* the process group is already gone */
        }
      }
      try { child?.kill("SIGTERM"); } catch { /* already gone */ }
    },
  };
  active.set(basename(audio), slot);
  return slot;
}

/** Stops the whisperX process for this audio file, including one started by collection rather than the queue. */
export function cancelTranscribe(file: string): boolean {
  const slot = active.get(basename(file));
  if (!slot) return false;
  slot.kill();
  return true;
}

export function venvPython(bin: string): string | null {
  const py = join(dirname(bin), process.platform === "win32" ? "python.exe" : "python");
  return existsSync(py) ? py : null;
}

type SpeakerJob = {
  bin: string;
  audio: string;
  jsonPath: string;
  transcript: string;
  /** pyannote with a Hugging Face token, or sherpa-onnx (`token` empty) — see diarize.ts. */
  engine: "pyannote" | "onnx";
  token: string;
  threads: number;
  onSpeakers?: (file: string) => void;
  /** Stopped by the user while the pass ran: leave the transcript as it was. */
  cancelled?: () => boolean;
};

let speakerChain: Promise<void> = Promise.resolve();

function scheduleSpeakers(job: SpeakerJob): void {
  speakerChain = speakerChain.then(() => labelSpeakers(job)).catch((err) => console.error(`화자 구분 실패: ${(err as Error).message || String(err)}`));
}

/** Runs one speaker pass after any already scheduled one, and rejects when it fails. */
function speakersNow(job: SpeakerJob): Promise<void> {
  const run = speakerChain.then(() => labelSpeakers(job));
  speakerChain = run.catch(() => {});
  return run;
}

/** Writes "[A] …" turns into the transcript. Throws (with any token masked) when the pass fails. */
async function labelSpeakers(job: SpeakerJob): Promise<void> {
  const py = venvPython(job.bin);
  const onnx = job.engine === "onnx";
  const script = join(dirname(fileURLToPath(import.meta.url)), onnx ? "diarize_onnx.py" : "diarize_later.py");
  try {
    if (!py || !existsSync(script)) throw new Error("whisperX 환경에서 화자 구분 스크립트를 찾지 못했습니다");
    if (!existsSync(job.audio)) throw new Error("원본 녹음이 없습니다");
    // the first transcript that needs speakers brings sherpa-onnx and the models (about 33 MB)
    if (onnx && !(await ensureDiarizer(py, { log: (l) => console.log(`[speakers] ${l}`) }))) throw new Error("화자 구분 모델을 준비하지 못했습니다");
    const args = onnx ? [script, job.audio, job.jsonPath, diarizeDir()] : [script, job.audio, job.jsonPath];
    const text = await new Promise<string>((resolve, reject) => {
      const child = spawnBin(py, args, {
        env: { ...process.env, PYTHONUNBUFFERED: "1", ...(job.token ? { HF_TOKEN: job.token } : {}), OMP_NUM_THREADS: String(job.threads), ZAEVIS_DIARIZE_THREADS: String(job.threads), PATH: [dirname(py), process.env.PATH ?? ""].filter(Boolean).join(delimiter) },
        stdio: ["ignore", "pipe", "pipe"],
      });
      let out = "";
      let err = "";
      child.stdout?.on("data", (b: Buffer) => { out += b.toString(); });
      child.stderr?.on("data", (b: Buffer) => { err = (err + b.toString()).slice(-4000); });
      const killer = setTimeout(() => child.kill("SIGTERM"), 3 * 60 * 60_000);
      child.on("error", (e) => { clearTimeout(killer); reject(e); });
      child.on("close", (code) => {
        clearTimeout(killer);
        if (code === 0 && out.trim()) resolve(out);
        else reject(new Error(err.trim().split("\n").slice(-3).join(" ") || `종료 ${code}`));
      });
    });
    if (job.cancelled?.()) return;
    const raw = await readFile(job.transcript, "utf8");
    const header = transcriptHeader(raw);
    await writeFile(job.transcript, `${header ? `${header}\n\n` : ""}${redact(formatSpeakerTurns(text))}\n`);
    const name = basename(job.transcript);
    try { job.onSpeakers?.(name); } catch {}
    notify("화자 구분 완료", `${name}에 말한 사람을 붙였습니다.`);
  } catch (err) {
    const msg = (err as Error).message || String(err);
    throw new Error(job.token ? msg.replaceAll(job.token, "…") : msg);
  } finally {
    await rm(job.jsonPath, { force: true }).catch(() => {});
  }
}

/** One whisperX pass: <audio stem>.txt and .json in [outDir]. Rejects with TranscribeCancelled when [slot] is stopped. */
async function runWhisperx(bin: string, audio: string, outDir: string, threads: number, slot: ActiveRun, opts: TranscribeOptions): Promise<void> {
  const args = transcribeLaunchArgs(audio, outDir, { model: opts.model, language: opts.language, threads });
  let view: WhisperView = { label: "모델 불러오는 중", fraction: null };
  const emit = () => opts.onProgress?.({ line: whisperStatusLine(view), fraction: view.fraction });
  emit();
  await new Promise<void>((resolve, reject) => {
    // whisperX shells out to `ffmpeg`; the extension links one next to the whisperx binary.
    // PYTHONUNBUFFERED so each "Progress: N%" line arrives before the buffer fills.
    // detached puts ffmpeg in the same process group so cancel reaches it too.
    const env = {
      ...process.env,
      PYTHONUNBUFFERED: "1",
      OMP_NUM_THREADS: String(threads),
      MKL_NUM_THREADS: String(threads),
      PATH: [dirname(bin), process.env.PATH ?? ""].filter(Boolean).join(delimiter),
    };
    if (slot.cancelled) {
      reject(new TranscribeCancelled());
      return;
    }
    const child = spawnBin(bin, args, { env, stdio: ["ignore", "pipe", "pipe"], detached: process.platform !== "win32" });
    slot.child = child;
    let errText = "";
    const take = (buf: Buffer) => {
      const chunk = buf.toString();
      errText = (errText + chunk).slice(-4000);
      for (const line of textLines(chunk)) {
        opts.onBeat?.(line.slice(0, 160));
        const next = foldWhisperLine(view, line);
        if (next) {
          view = next;
          emit();
        }
      }
    };
    child.stdout?.on("data", take);
    child.stderr?.on("data", take);
    const timer = setInterval(() => opts.onTick?.(), 5000);
    const killer = setTimeout(() => child.kill("SIGTERM"), 3 * 60 * 60_000);
    let settled = false;
    const finish = (err?: Error) => {
      if (settled) return;
      settled = true;
      clearInterval(timer);
      clearTimeout(killer);
      if (err) reject(err);
      else resolve();
    };
    child.on("error", (e) => finish(slot.cancelled ? new TranscribeCancelled() : e));
    child.on("close", (code) => {
      if (slot.cancelled) finish(new TranscribeCancelled());
      else if (code === 0) finish();
      else {
        const tail = errText.trim().split("\n").slice(-3).join(" ");
        finish(new Error(`whisperX 실패: ${tail || `종료 ${code}`}`));
      }
    });
  });
}

/** The title and "(whisperX …)" note of a transcript: everything a speaker pass keeps. */
export function transcriptHeader(raw: string): string {
  const marker = raw.indexOf("(whisperX ");
  const splitAt = marker >= 0 ? raw.indexOf("\n\n", marker) : -1;
  if (splitAt >= 0) return raw.slice(0, splitAt);
  if (marker >= 0) return raw.trimEnd();
  const title = raw.split("\n")[0] ?? "";
  return title.startsWith("# ") ? title : "";
}

/**
 * Transcribes one audio file into worklog/inbox/transcripts/<date>_<name>.txt and moves the
 * audio to worklog/processed/audio/. Returns as soon as the text is saved. Speaker labels,
 * when a Hugging Face login can call the models, are written into that file afterwards.
 */
export async function transcribeFile(audio: string, worklogDir: string, opts: TranscribeOptions = {}): Promise<string> {
  const bin = whisperxBin(opts.whisperxBin);
  if (!bin) throw new Error("whisperX가 설치되지 않았습니다. 'zaevis ext install whisperx'를 실행하세요.");
  const slot = trackRun(audio);
  let out: string | undefined;
  try {
    if (slot.cancelled) throw new TranscribeCancelled();
    const dir = await mkdtemp(join(tmpdir(), "zaevis-wx-"));
    out = dir;
    if (slot.cancelled) throw new TranscribeCancelled();
    const threads = transcribeThreads(opts.speed);
    await runWhisperx(bin, audio, dir, threads, slot, opts);
    if (slot.cancelled) throw new TranscribeCancelled();
    const produced = join(dir, basename(audio, extname(audio)) + ".txt");
    const text = (await readFile(produced, "utf8")).trim();
    const stem = await datedStem(audio);
    const dest = uniquePath(join(worklogDir, "inbox", "transcripts"), stem, ".txt");
    await mkdir(join(worklogDir, "inbox", "transcripts"), { recursive: true });
    await writeFile(dest, `# ${stem}\n\n(whisperX ${opts.model ?? "large-v3-turbo"} 자동 전사)\n\n${redact(text)}\n`);
    const audioDest = uniquePath(join(worklogDir, "processed", "audio"), basename(audio, extname(audio)), extname(audio));
    await moveFile(audio, audioDest);
    const jsonSrc = join(dir, basename(audio, extname(audio)) + ".json");
    if (opts.speakers !== false && existsSync(jsonSrc)) {
      const hf = opts.hfToken ?? await tokenForDiarize().catch(() => null);
      const jsonCopy = join(tmpdir(), `zaevis-diarize-${process.pid}-${Date.now()}.json`);
      await copyFile(jsonSrc, jsonCopy);
      scheduleSpeakers({ bin, audio: audioDest, jsonPath: jsonCopy, transcript: dest, engine: hf ? "pyannote" : "onnx", token: hf ?? "", threads, onSpeakers: opts.onSpeakers });
    }
    return dest;
  } finally {
    if (active.get(basename(audio)) === slot) active.delete(basename(audio));
    if (out) await rm(out, { recursive: true, force: true }).catch(() => {});
  }
}

/**
 * The kept recording behind a transcript in processed/audio/: same name ("2026-11-02_1703_녹음"), or the name
 * before the date was added ("2026-10-21_회의.txt" ← "회의.m4a"). Null when it was not kept.
 */
export async function audioForTranscript(worklogDir: string, transcript: string): Promise<string | null> {
  const dir = join(worklogDir, "processed", "audio");
  const stem = basename(transcript, extname(transcript));
  const stems = [stem, stem.replace(/^\d{4}-\d{2}-\d{2}_/, "")];
  let names: string[];
  try {
    names = await readdir(dir);
  } catch {
    return null;
  }
  for (const want of stems) {
    const hit = names.find((n) => AUDIO_EXT.has(extname(n).toLowerCase()) && basename(n, extname(n)) === want);
    if (hit) return join(dir, hit);
  }
  return null;
}

/**
 * Speaker labels for a transcript saved without them (before diarization existed, or with it off): recognizes the
 * kept recording again for timings, then rewrites the text below the header as "[A] …" turns. The file changes
 * only when the speaker pass succeeds; names given earlier are replaced by letters again.
 */
export async function relabelTranscript(transcript: string, worklogDir: string, opts: TranscribeOptions = {}): Promise<string> {
  const bin = whisperxBin(opts.whisperxBin);
  if (!bin) throw new Error("whisperX가 설치되지 않았습니다. 'zaevis ext install whisperx'를 실행하세요.");
  const audio = await audioForTranscript(worklogDir, transcript);
  if (!audio) throw new Error("원본 녹음이 processed/audio에 없어 화자를 붙일 수 없습니다");
  const slot = trackRun(transcript);
  let out: string | undefined;
  try {
    out = await mkdtemp(join(tmpdir(), "zaevis-wx-"));
    const threads = transcribeThreads(opts.speed);
    await runWhisperx(bin, audio, out, threads, slot, {
      ...opts,
      onProgress: (p) => opts.onProgress?.({ line: `다시 인식 · ${p.line}`, fraction: p.fraction == null ? null : p.fraction * 0.6 }),
    });
    if (slot.cancelled) throw new TranscribeCancelled();
    const json = join(out, basename(audio, extname(audio)) + ".json");
    if (!existsSync(json)) throw new Error("whisperX가 시간 정보(JSON)를 남기지 않았습니다");
    const jsonCopy = join(tmpdir(), `zaevis-diarize-${process.pid}-${Date.now()}.json`);
    await copyFile(json, jsonCopy);
    opts.onProgress?.({ line: "화자 구분 중", fraction: 0.6 });
    const hf = opts.hfToken ?? await tokenForDiarize().catch(() => null);
    await speakersNow({ bin, audio, jsonPath: jsonCopy, transcript, engine: hf ? "pyannote" : "onnx", token: hf ?? "", threads, onSpeakers: opts.onSpeakers, cancelled: () => slot.cancelled });
    if (slot.cancelled) throw new TranscribeCancelled();
    return transcript;
  } finally {
    if (active.get(basename(transcript)) === slot) active.delete(basename(transcript));
    if (out) await rm(out, { recursive: true, force: true }).catch(() => {});
  }
}

export type TranscribeJobState = "queued" | "running" | "done" | "failed" | "cancelled";

export type TranscribeJob = {
  file: string;
  /** "speakers": a speaker pass for an existing transcript (file is the transcript's name). */
  kind?: "transcribe" | "speakers";
  state: TranscribeJobState;
  result?: string;
  error?: string;
  at: string;
  line?: string;
  fraction?: number | null;
};

/** One transcription at a time; uploads queue up behind each other. */
export class TranscribeQueue {
  private chain: Promise<unknown> = Promise.resolve();
  private readonly stopping = new WeakSet<TranscribeJob>();
  readonly jobs: TranscribeJob[] = [];

  /** Called when a job finishes either way (the server turns this into an OS notification). Cancel does not call this. */
  onDone?: (job: TranscribeJob) => void;

  /** Stops a queued or running job. The audio stays in the inbox so it can be tried again. */
  cancel(file: string): boolean {
    const name = basename(file);
    const jobs = this.jobs.filter((j) => j.file === name && (j.state === "queued" || j.state === "running"));
    const killed = cancelTranscribe(name);
    if (!jobs.length && !killed) return false;
    for (const job of jobs) {
      this.stopping.add(job);
      job.fraction = null;
      if (job.state === "queued") {
        job.state = "cancelled";
        job.line = "취소했습니다";
      } else {
        job.line = "취소하는 중";
      }
    }
    return true;
  }

  enqueue(audio: string, worklogDir: string, opts: TranscribeOptions): void {
    this.add(audio, "transcribe", opts, (o) => transcribeFile(audio, worklogDir, o));
  }

  /** Queues a speaker pass for a transcript that has none (see relabelTranscript). The job's file is the transcript's name. */
  enqueueRelabel(transcript: string, worklogDir: string, opts: TranscribeOptions): void {
    this.add(transcript, "speakers", opts, (o) => relabelTranscript(transcript, worklogDir, o));
  }

  private add(file: string, kind: TranscribeJob["kind"], opts: TranscribeOptions, run: (opts: TranscribeOptions) => Promise<string>): void {
    const job: TranscribeJob = { file: basename(file), kind, state: "queued", at: new Date().toISOString() };
    this.jobs.unshift(job);
    this.jobs.splice(20);
    this.chain = this.chain.then(async () => {
      if (this.stopping.has(job) || job.state === "cancelled") {
        job.state = "cancelled";
        job.line = "취소했습니다";
        job.fraction = null;
        return;
      }
      job.state = "running";
      try {
        job.result = basename(await run({
          ...opts,
          onProgress: (p) => {
            if (this.stopping.has(job)) return;
            job.line = p.line;
            job.fraction = p.fraction;
            opts.onProgress?.(p);
          },
        }));
        job.state = "done";
        job.fraction = 1;
      } catch (err) {
        if (this.stopping.has(job) || (err as Error).name === "TranscribeCancelled") {
          job.state = "cancelled";
          job.error = undefined;
          job.line = "취소했습니다";
          job.fraction = null;
          return;
        }
        job.state = "failed";
        job.error = (err as Error).message;
      }
      try {
        this.onDone?.(job);
      } catch {}
    });
  }

  get busy(): boolean {
    return this.jobs.some((j) => j.state === "queued" || j.state === "running");
  }
}
