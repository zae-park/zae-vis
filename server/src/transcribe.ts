// Audio → text with whisperX (optional extension, installed by `zaevis ext install whisperx`).
// Recognition runs first and the text is saved before anyone waits on speakers. CTranslate2 on
// this build has no GPU backend, so the one process uses every CPU core, skips the alignment
// model, and leaves pyannote for a later pass that rewrites the same file.

import { spawnBin } from "./spawnbin.ts";
import type { ChildProcess } from "node:child_process";
import { existsSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { availableParallelism, tmpdir } from "node:os";
import { basename, delimiter, dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { expandHome, stateDir } from "./config.ts";
import { tokenForDiarize } from "./hf.ts";
import { notify } from "./notify.ts";
import { redact } from "./redact.ts";
import { dayKey } from "./sources/types.ts";

export const AUDIO_EXT = new Set([".m4a", ".mp3", ".wav", ".aac", ".flac", ".ogg", ".opus", ".webm", ".mp4", ".mov", ".m4v"]);
export const TEXT_EXT = new Set([".txt", ".md", ".vtt", ".srt"]);

export type TranscribeOptions = {
  language?: string;
  model?: string;
  whisperxBin?: string;
  hfToken?: string;
  /** A line whisperX printed. */
  onBeat?: (line: string) => void;
  /** Still inside this file, even when whisperX has not printed anything. */
  onTick?: () => void;
  /** Korean status and a 0–1 fraction. Fraction is null while a phase has not reported a percent yet. */
  onProgress?: (p: { line: string; fraction: number | null }) => void;
  /** Fired when a later speaker pass rewrites the transcript. The text is already saved by then. */
  onSpeakers?: (file: string) => void;
};

/** CPU threads for the one recognition process. CTranslate2 here has no GPU device. */
export function transcribeThreads(): number {
  return Math.max(1, availableParallelism());
}

/** Arguments for the fast pass: text first, no alignment model, no speaker labels. */
export function transcribeLaunchArgs(audio: string, outDir: string, opts: { model?: string; language?: string; threads?: number } = {}): string[] {
  return [
    audio,
    "--model", opts.model ?? "large-v3-turbo",
    "--language", opts.language ?? "ko",
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

function venvPython(bin: string): string | null {
  const py = join(dirname(bin), process.platform === "win32" ? "python.exe" : "python");
  return existsSync(py) ? py : null;
}

type SpeakerJob = {
  bin: string;
  audio: string;
  jsonPath: string;
  transcript: string;
  token: string;
  onSpeakers?: (file: string) => void;
};

let speakerChain: Promise<void> = Promise.resolve();

function scheduleSpeakers(job: SpeakerJob): void {
  speakerChain = speakerChain.then(() => labelSpeakers(job)).catch(() => {});
}

async function labelSpeakers(job: SpeakerJob): Promise<void> {
  const py = venvPython(job.bin);
  const script = join(dirname(fileURLToPath(import.meta.url)), "diarize_later.py");
  const fail = (msg: string) => console.error(`화자 구분 실패: ${msg.replaceAll(job.token, "…")}`);
  try {
    if (!py || !existsSync(script) || !existsSync(job.audio)) return;
    const text = await new Promise<string>((resolve, reject) => {
      const child = spawnBin(py, [script, job.audio, job.jsonPath], {
        env: { ...process.env, PYTHONUNBUFFERED: "1", HF_TOKEN: job.token, PATH: [dirname(py), process.env.PATH ?? ""].filter(Boolean).join(delimiter) },
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
    const raw = await readFile(job.transcript, "utf8");
    const marker = raw.indexOf("(whisperX ");
    const splitAt = marker >= 0 ? raw.indexOf("\n\n", marker) : -1;
    const header = splitAt >= 0 ? raw.slice(0, splitAt) : raw.trimEnd();
    await writeFile(job.transcript, `${header}\n\n${redact(text.trim())}\n`);
    const name = basename(job.transcript);
    try { job.onSpeakers?.(name); } catch {}
    notify("화자 구분 완료", `${name}에 말한 사람을 붙였습니다.`);
  } catch (err) {
    fail((err as Error).message || String(err));
  } finally {
    await rm(job.jsonPath, { force: true }).catch(() => {});
  }
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
    const threads = transcribeThreads();
    const args = transcribeLaunchArgs(audio, dir, { model: opts.model, language: opts.language, threads });
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
    const hf = opts.hfToken ?? await tokenForDiarize().catch(() => null);
    if (hf && existsSync(jsonSrc)) {
      const jsonCopy = join(tmpdir(), `zaevis-diarize-${process.pid}-${Date.now()}.json`);
      await copyFile(jsonSrc, jsonCopy);
      scheduleSpeakers({ bin, audio: audioDest, jsonPath: jsonCopy, transcript: dest, token: hf, onSpeakers: opts.onSpeakers });
    }
    return dest;
  } finally {
    if (active.get(basename(audio)) === slot) active.delete(basename(audio));
    if (out) await rm(out, { recursive: true, force: true }).catch(() => {});
  }
}

export type TranscribeJobState = "queued" | "running" | "done" | "failed" | "cancelled";

export type TranscribeJob = {
  file: string;
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
    const job: TranscribeJob = { file: basename(audio), state: "queued", at: new Date().toISOString() };
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
        job.result = basename(await transcribeFile(audio, worklogDir, {
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
