// Audio → text with whisperX (optional extension, installed by `zaevis ext install whisperx`).

import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, extname, join } from "node:path";
import { expandHome, stateDir } from "./config.ts";
import { redact } from "./redact.ts";
import { dayKey } from "./sources/types.ts";

export const AUDIO_EXT = new Set([".m4a", ".mp3", ".wav", ".aac", ".flac", ".ogg", ".opus", ".webm", ".mp4", ".mov", ".m4v"]);
export const TEXT_EXT = new Set([".txt", ".md", ".vtt", ".srt"]);

export type TranscribeOptions = { language?: string; model?: string; whisperxBin?: string; hfToken?: string };

export function whisperxBin(explicit?: string): string | null {
  const candidates = [explicit, process.env.ZAEVIS_WHISPERX, join(stateDir(), "ext", "whisperx", "bin", "whisperx")].filter(Boolean) as string[];
  for (const c of candidates) if (existsSync(expandHome(c))) return expandHome(c);
  for (const dir of (process.env.PATH ?? "").split(":")) if (dir && existsSync(join(dir, "whisperx"))) return join(dir, "whisperx");
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
    const hf = opts.hfToken ?? process.env.HF_TOKEN;
    if (hf) args.push("--diarize", "--hf_token", hf);
    await new Promise<void>((resolve, reject) => {
      execFile(bin, args, { maxBuffer: 64 * 1024 * 1024, timeout: 3 * 60 * 60_000 }, (err, _so, se) =>
        err ? reject(new Error(`whisperX 실패: ${String(se || err.message).trim().split("\n").slice(-3).join(" ")}`)) : resolve(),
      );
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
    });
  }

  get busy(): boolean {
    return this.jobs.some((j) => j.state === "queued" || j.state === "running");
  }
}
