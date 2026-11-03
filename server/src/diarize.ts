// Speaker labels without an account. sherpa-onnx runs the pyannote segmentation-3.0 model and the
// WeSpeaker ResNet34 embedding (the pair pyannote 3.1 itself uses) as ONNX files published on
// k2-fsa/sherpa-onnx's GitHub releases, so nothing asks for a Hugging Face login or a model consent.
// The package goes into the whisperX venv; the models into `$ZAEVIS_HOME/ext/diarize`. Both arrive
// once, the first time a transcript needs speakers (or with `zaevis ext install whisperx|diarize`).

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { delimiter, dirname, join } from "node:path";
import { stateDir } from "./config.ts";
import { findBin } from "./digest.ts";
import { downloadVerified, tarExtract, type KiwiAsset } from "./kiwi.ts";

export const SHERPA_ONNX_VERSION = "2.0.1";

type Asset = KiwiAsset & { url: string };

/** sha256 and sizes pinned from the release files (the releases publish no digests for these assets). */
export const DIARIZE_ASSETS: { segmentation: Asset; embedding: Asset } = {
  segmentation: {
    name: "sherpa-onnx-pyannote-segmentation-3-0.tar.bz2",
    sha256: "24615ee884c897d9d2ba09bb4d30da6bb1b15e685065962db5b02e76e4996488",
    bytes: 6958444,
    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2",
  },
  embedding: {
    name: "wespeaker_en_voxceleb_resnet34_LM.onnx",
    sha256: "e9848563da86f263117134dfd7ad63c92355b37de492b55e325400c9d9c39012",
    bytes: 26530550,
    // (sic) the release tag is spelled "recongition"
    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx",
  },
};

export const SEGMENTATION_FILE = "segmentation.onnx";
export const EMBEDDING_FILE = "embedding.onnx";

export const diarizeDir = (): string => join(stateDir(), "ext", "diarize");

export type DiarizerState = "unavailable" | "missing" | "installing" | "ready" | "failed";
export type DiarizerStatus = { state: DiarizerState; error?: string; dir: string; downloadMb: number };

/** The venv's site-packages (lib/python3.x/site-packages, or Lib/site-packages on Windows). */
function sitePackages(python: string): string[] {
  const venv = dirname(dirname(python));
  const out = [join(venv, "Lib", "site-packages")];
  try {
    for (const d of readdirSync(join(venv, "lib"))) if (d.startsWith("python")) out.push(join(venv, "lib", d, "site-packages"));
  } catch {}
  return out;
}

export function sherpaInstalled(python: string): boolean {
  return sitePackages(python).some((d) => existsSync(join(d, "sherpa_onnx")));
}

export function modelsReady(dir = diarizeDir()): boolean {
  return existsSync(join(dir, SEGMENTATION_FILE)) && existsSync(join(dir, EMBEDDING_FILE));
}

let installing: Promise<void> | null = null;
let lastError: string | null = null;

export function diarizerStatus(python: string | null, dir = diarizeDir()): DiarizerStatus {
  const downloadMb = Math.round((DIARIZE_ASSETS.segmentation.bytes + DIARIZE_ASSETS.embedding.bytes) / 1_000_000);
  if (!python) return { state: "unavailable", dir, downloadMb };
  if (installing) return { state: "installing", dir, downloadMb };
  if (sherpaInstalled(python) && modelsReady(dir)) return { state: "ready", dir, downloadMb };
  if (lastError) return { state: "failed", error: lastError, dir, downloadMb };
  return { state: "missing", dir, downloadMb };
}

/** uv on PATH, or the one `zaevis ext install whisperx` dropped into the state folder. */
export function findUv(): string | null {
  const own = join(stateDir(), "ext", "uv", process.platform === "win32" ? "uv.exe" : "uv");
  return findBin("uv") ?? (existsSync(own) ? own : null);
}

export type InstallOptions = {
  python: string;
  dir?: string;
  uv?: string | null;
  fetchImpl?: typeof fetch;
  log?: (line: string) => void;
  /** Runs a command; tests pass a fake. */
  run?: (cmd: string, args: string[]) => Promise<void>;
  /** Tests point the downloads at small local files. */
  assets?: { segmentation: Asset; embedding: Asset };
};

const runCmd = (cmd: string, args: string[]): Promise<void> =>
  new Promise((res, rej) => {
    const child = spawn(cmd, args, { stdio: ["ignore", "ignore", "pipe"], windowsHide: true, env: { ...process.env, PATH: [dirname(cmd), process.env.PATH ?? ""].join(delimiter) } });
    let err = "";
    child.stderr?.on("data", (d) => (err = (err + String(d)).slice(-2000)));
    child.on("error", rej);
    child.on("close", (code) => (code === 0 ? res() : rej(new Error(`${cmd} 종료 ${code}: ${err.trim().split("\n").slice(-2).join(" ")}`))));
  });

/** Puts sherpa-onnx into the whisperX venv and the two models into `dir`. Skips what is already there. */
export async function installDiarizer(opts: InstallOptions): Promise<void> {
  const dir = opts.dir ?? diarizeDir();
  const log = opts.log ?? (() => {});
  const run = opts.run ?? runCmd;
  if (!sherpaInstalled(opts.python)) {
    const uv = opts.uv === undefined ? findUv() : opts.uv;
    log(`sherpa-onnx ${SHERPA_ONNX_VERSION} 설치 중 (화자 구분)`);
    if (uv) await run(uv, ["pip", "install", "--python", opts.python, `sherpa-onnx==${SHERPA_ONNX_VERSION}`]);
    else await run(opts.python, ["-m", "pip", "install", `sherpa-onnx==${SHERPA_ONNX_VERSION}`]);
  }
  if (modelsReady(dir)) return;
  mkdirSync(dir, { recursive: true });
  const { segmentation, embedding } = opts.assets ?? DIARIZE_ASSETS;
  log(`화자 모델 받는 중 (${Math.round((segmentation.bytes + embedding.bytes) / 1_000_000)} MB)`);
  const tmp = join(dir, "download");
  mkdirSync(tmp, { recursive: true });
  try {
    const archive = join(tmp, segmentation.name);
    await downloadVerified(segmentation.url, archive, segmentation, opts.fetchImpl, log);
    const inner = "sherpa-onnx-pyannote-segmentation-3-0";
    await tarExtract(archive, tmp, [`${inner}/model.onnx`, `${inner}/LICENSE`]);
    renameSync(join(tmp, inner, "model.onnx"), join(dir, SEGMENTATION_FILE));
    renameSync(join(tmp, inner, "LICENSE"), join(dir, "LICENSE-pyannote-segmentation-3.0"));
    await downloadVerified(embedding.url, join(dir, EMBEDDING_FILE), embedding, opts.fetchImpl, log);
    writeFileSync(join(dir, "VERSION"), `sherpa-onnx ${SHERPA_ONNX_VERSION}\n${segmentation.name} ${segmentation.sha256}\n${embedding.name} ${embedding.sha256}\n`);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

/**
 * Makes sure speakers can be labeled, installing once in the background. Concurrent callers share the
 * install. Resolves true when ready; false (with the reason in `diarizerStatus`) when it failed.
 */
export function ensureDiarizer(python: string, opts: Omit<InstallOptions, "python"> = {}): Promise<boolean> {
  if (sherpaInstalled(python) && modelsReady(opts.dir)) return Promise.resolve(true);
  if (!installing) {
    lastError = null;
    installing = installDiarizer({ ...opts, python })
      .catch((err) => {
        lastError = (err as Error).message;
        opts.log?.(`화자 구분 준비 실패: ${lastError}`);
      })
      .finally(() => {
        installing = null;
      });
  }
  return installing.then(() => sherpaInstalled(python) && modelsReady(opts.dir));
}

/** A, B, … Z, then 화자27 … — the order speakers first speak in. */
export function speakerLetter(i: number): string {
  return i < 26 ? String.fromCharCode(65 + i) : `화자${i + 1}`;
}

/** Splits after sentence ends (. ? ! and their full-width forms). */
function splitSentences(text: string): string[] {
  return text.split(/(?<=[.?!。？！])\s+/).map((s) => s.trim()).filter(Boolean);
}

/**
 * Speaker output from either engine — lines like "[SPEAKER_01]: …" (pyannote) or "[S3]: …" (sherpa-onnx) —
 * as a readable transcript: one block per turn starting with "[A] ", a blank line between turns, and a line
 * break every couple of sentences (about [width] characters) inside a long turn. Unlabeled lines join the turn
 * before them.
 */
export function formatSpeakerTurns(raw: string, width = 80): string {
  const letters = new Map<string, string>();
  const turns: Array<{ who: string | null; text: string[] }> = [];
  for (const line of raw.split("\n")) {
    const t = line.trim();
    if (!t) continue;
    const m = /^\[([^\]]+)\]:\s*(.*)$/.exec(t);
    const id = m ? m[1] : null;
    const text = (m ? m[2] : t).trim();
    if (!text) continue;
    let who: string | null = null;
    if (id !== null) {
      if (!letters.has(id)) letters.set(id, speakerLetter(letters.size));
      who = letters.get(id)!;
    }
    const prev = turns.at(-1);
    if (prev && (who === null || who === prev.who)) prev.text.push(text);
    else turns.push({ who, text: [text] });
  }
  return turns
    .map((turn) => {
      const lines: string[] = [];
      let cur = "";
      for (const sentence of splitSentences(turn.text.join(" "))) {
        // break before a sentence that would run past the width, so lines stay about [width] long
        if (cur && cur.length + 1 + sentence.length > width) {
          lines.push(cur);
          cur = sentence;
        } else cur = cur ? `${cur} ${sentence}` : sentence;
      }
      if (cur) lines.push(cur);
      return (turn.who ? `[${turn.who}] ` : "") + lines.join("\n");
    })
    .join("\n\n");
}

/** The speaker labels a transcript uses, in order of appearance: "[A] …" at the start of a turn. */
export function transcriptSpeakers(text: string): string[] {
  const seen: string[] = [];
  for (const m of text.matchAll(/^\[([^\]\n]{1,24})\] /gm)) if (!seen.includes(m[1])) seen.push(m[1]);
  return seen;
}

/** A name a speaker label can take: one line, no brackets, at most 20 characters. */
export function cleanSpeakerName(name: string): string | null {
  const n = name.replace(/[\[\]\r\n]/g, "").trim();
  return n && n.length <= 20 ? n : null;
}

/**
 * Renames speakers in a transcript ("[A] " → "[재박] ") at the start of turns only. Renaming two labels to each
 * other works because every turn is rewritten from the original label in one pass.
 */
export function renameSpeakers(text: string, names: Record<string, string>): string {
  return text.replace(/^\[([^\]\n]{1,24})\] /gm, (whole, label: string) => {
    const next = names[label];
    return next ? `[${next}] ` : whole;
  });
}
