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
};

function lastProgressLine(chunk: string): string | null {
  const lines = chunk
    .replace(/\u001b\[[0-9;]*[A-Za-z]/g, "")
    .replace(/\r/g, "\n")
    .split("\n")
    .map((s) => s.trim())
    .filter(Boolean);
  const line = lines.at(-1);
  return line ? line.slice(0, 160) : null;
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
    const args = [audio, "--model", opts.model ?? "large-v3-turbo", "--language", opts.language ?? "ko", "--compute_type", "int8", "--device", "cpu", "--output_dir", out, "--output_format", "txt"];
    const hf = opts.hfToken ?? (await tokenForDiarize());
    if (hf) args.push("--diarize", "--hf_token", hf);
    await new Promise<void>((resolve, reject) => {
      // whisperX shells out to `ffmpeg`; the extension links one next to the whisperx binary.
      const env = { ...process.env, PATH: [dirname(bin), process.env.PATH ?? ""].filter(Boolean).join(delimiter), ...(hf ? { HF_TOKEN: hf } : {}) };
      const child = spawnBin(bin, args, { env, stdio: ["ignore", "pipe", "pipe"] });
      let errText = "";
      const take = (buf: Buffer) => {
        const chunk = buf.toString();
        errText = (errText + chunk).slice(-4000);
        const line = lastProgressLine(chunk);
        if (line) opts.onBeat?.(hf ? line.replaceAll(hf, "…") : line);
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
  readonly jobs: Array<{ file: string; state: "queued" | "running" | "done" | "failed"; result?: string; error?: string; at: string }> = [];

  /** Called when a job finishes either way (the server turns this into an OS notification). */
  onDone?: (job: TranscribeQueue["jobs"][number]) => void;

  enqueue(audio: string, worklogDir: string, opts: TranscribeOptions): void {
    const job = { file: basename(audio), state: "queued" as const, at: new Date().toISOString() } as (typeof this.jobs)[number];
    this.jobs.unshift(job);
    this.jobs.splice(20);
    this.chain = this.chain.then(async () => {
      job.state = "running";
      try {
        job.result = basename(await transcribeFile(audio, worklogDir, opts));
        job.state = "done";
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
