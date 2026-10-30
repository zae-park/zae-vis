// Audio → text with whisperX (optional extension, installed by `zaevis ext install whisperx`).
// Speaker labels are added only after the app's Hugging Face login has a token and the pyannote
// models have been accepted. A missing login still transcribes; it just does not diarize.

import { spawnBin } from "./spawnbin.ts";
import { existsSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, delimiter, dirname, extname, join } from "node:path";
import { expandHome, stateDir } from "./config.ts";
import { tokenForDiarize } from "./hf.ts";
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
};

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

/**
 * Transcribes one audio file into worklog/inbox/transcripts/<date>_<name>.txt and moves the
 * audio to worklog/processed/audio/. Returns the transcript path.
 */
export async function transcribeFile(audio: string, worklogDir: string, opts: TranscribeOptions = {}): Promise<string> {
  const bin = whisperxBin(opts.whisperxBin);
  if (!bin) throw new Error("whisperX가 설치되지 않았습니다. 'zaevis ext install whisperx'를 실행하세요.");
  const out = await mkdtemp(join(tmpdir(), "zaevis-wx-"));
  try {
    const args = [audio, "--model", opts.model ?? "large-v3-turbo", "--language", opts.language ?? "ko", "--compute_type", "int8", "--device", "cpu", "--output_dir", out, "--output_format", "txt", "--print_progress", "True", "--verbose", "False", "--log-level", "info"];
    const hf = opts.hfToken ?? (await tokenForDiarize());
    if (hf) args.push("--diarize", "--hf_token", hf);
    let view: WhisperView = { label: "모델 불러오는 중", fraction: null };
    const emit = () => opts.onProgress?.({ line: whisperStatusLine(view), fraction: view.fraction });
    emit();
    await new Promise<void>((resolve, reject) => {
      // whisperX shells out to `ffmpeg`; the extension links one next to the whisperx binary.
      // PYTHONUNBUFFERED so each "Progress: N%" line arrives before the buffer fills.
      const env = { ...process.env, PYTHONUNBUFFERED: "1", PATH: [dirname(bin), process.env.PATH ?? ""].filter(Boolean).join(delimiter), ...(hf ? { HF_TOKEN: hf } : {}) };
      const child = spawnBin(bin, args, { env, stdio: ["ignore", "pipe", "pipe"] });
      let errText = "";
      const take = (buf: Buffer) => {
        const chunk = hf ? buf.toString().replaceAll(hf, "…") : buf.toString();
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
      const finish = (err?: Error) => {
        clearInterval(timer);
        clearTimeout(killer);
        if (err) reject(err);
        else resolve();
      };
      child.on("error", (e) => finish(e));
      child.on("close", (code) => {
        if (code === 0) finish();
        else {
          const tail = errText.trim().split("\n").slice(-3).join(" ");
          finish(new Error(`whisperX 실패: ${hf ? tail.replaceAll(hf, "…") : tail || `종료 ${code}`}`));
        }
      });
    });
    const produced = join(out, basename(audio, extname(audio)) + ".txt");
    const text = (await readFile(produced, "utf8")).trim();
    const stem = await datedStem(audio);
    const dest = uniquePath(join(worklogDir, "inbox", "transcripts"), stem, ".txt");
    await mkdir(join(worklogDir, "inbox", "transcripts"), { recursive: true });
    await writeFile(dest, `# ${stem}\n\n(whisperX ${opts.model ?? "large-v3-turbo"} 자동 전사)\n\n${redact(text)}\n`);
    await moveFile(audio, uniquePath(join(worklogDir, "processed", "audio"), basename(audio, extname(audio)), extname(audio)));
    return dest;
  } finally {
    await rm(out, { recursive: true, force: true }).catch(() => {});
  }
}

/** One transcription at a time; uploads queue up behind each other. */
export class TranscribeQueue {
  private chain: Promise<unknown> = Promise.resolve();
  readonly jobs: Array<{ file: string; state: "queued" | "running" | "done" | "failed"; result?: string; error?: string; at: string; line?: string; fraction?: number | null }> = [];

  /** Called when a job finishes either way (the server turns this into an OS notification). */
  onDone?: (job: TranscribeQueue["jobs"][number]) => void;

  enqueue(audio: string, worklogDir: string, opts: TranscribeOptions): void {
    const job = { file: basename(audio), state: "queued" as const, at: new Date().toISOString() } as (typeof this.jobs)[number];
    this.jobs.unshift(job);
    this.jobs.splice(20);
    this.chain = this.chain.then(async () => {
      job.state = "running";
      try {
        job.result = basename(await transcribeFile(audio, worklogDir, {
          ...opts,
          onProgress: (p) => {
            job.line = p.line;
            job.fraction = p.fraction;
            opts.onProgress?.(p);
          },
        }));
        job.state = "done";
        job.fraction = 1;
      } catch (err) {
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
