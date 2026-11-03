import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

process.env.ZAEVIS_HOME = await mkdtemp(join(tmpdir(), "zv-diarize-state-"));
const { DIARIZE_ASSETS, diarizerStatus, ensureDiarizer, installDiarizer, formatSpeakerTurns, renameSpeakers, SHERPA_ONNX_VERSION, speakerLetter, transcriptSpeakers } = await import("../src/diarize.ts");

const sha = (b: Buffer) => createHash("sha256").update(b).digest("hex");

/** A fake venv: bin/python plus lib/python3.12/site-packages. */
async function venv(): Promise<{ python: string; site: string }> {
  const root = await mkdtemp(join(tmpdir(), "zv-venv-"));
  mkdirSync(join(root, "bin"));
  writeFileSync(join(root, "bin", "python"), "");
  const site = join(root, "lib", "python3.12", "site-packages");
  mkdirSync(site, { recursive: true });
  return { python: join(root, "bin", "python"), site };
}

/** Release-shaped test files: the segmentation tarball and the embedding model. */
async function fakeAssets() {
  const work = await mkdtemp(join(tmpdir(), "zv-assets-"));
  const inner = join(work, "sherpa-onnx-pyannote-segmentation-3-0");
  mkdirSync(inner);
  writeFileSync(join(inner, "model.onnx"), "SEG");
  writeFileSync(join(inner, "LICENSE"), "MIT");
  writeFileSync(join(inner, "run.sh"), "x");
  const tar = join(work, "seg.tar.bz2");
  execFileSync("tar", ["-cjf", tar, "-C", work, "sherpa-onnx-pyannote-segmentation-3-0"]);
  const segBytes = readFileSync(tar);
  const emb = Buffer.from("EMBEDDING");
  const assets = {
    segmentation: { ...DIARIZE_ASSETS.segmentation, url: "https://example/seg.tar.bz2", sha256: sha(segBytes), bytes: segBytes.length },
    embedding: { ...DIARIZE_ASSETS.embedding, url: "https://example/emb.onnx", sha256: sha(emb), bytes: emb.length },
  };
  const fetched: string[] = [];
  const fetchImpl = (async (url: string) => {
    fetched.push(url);
    const body = url.endsWith("seg.tar.bz2") ? segBytes : url.endsWith("emb.onnx") ? emb : null;
    return body ? new Response(body) : new Response("nope", { status: 404 });
  }) as typeof fetch;
  return { assets, fetchImpl, fetched };
}

test("formatSpeakerTurns: A, B by first appearance, runs merged, a blank line between turns, long turns wrapped", () => {
  const raw = ["[S3]: 안녕하세요.", "[S3]: 오늘 볼 것은 색인입니다.", "[S0]: 네?", "그건 왜요?", "[S3]: 다시 만들기로 했어요.", "[SPEAKER_07]: 저도 들었어요."].join("\n");
  assert.equal(formatSpeakerTurns(raw), "[A] 안녕하세요. 오늘 볼 것은 색인입니다.\n\n[B] 네? 그건 왜요?\n\n[A] 다시 만들기로 했어요.\n\n[C] 저도 들었어요.");
  const long = Array.from({ length: 6 }, (_, i) => `[S1]: 문장 ${i + 1}번은 조금 길게 써서 줄을 넘기게 만듭니다.`).join("\n");
  const lines = formatSpeakerTurns(long, 60).split("\n");
  assert.ok(lines.length >= 3 && lines[0].startsWith("[A] ") && !lines[1].startsWith("["), lines.join(" | "));
  assert.equal(speakerLetter(0), "A");
  assert.equal(speakerLetter(25), "Z");
  assert.equal(speakerLetter(26), "화자27");
});

test("renameSpeakers names labels at turn starts only; swapping two names works", () => {
  const text = "# 회의\n\n(whisperX 자동 전사)\n\n[A] 안녕. [B]라고 부를게요.\n둘째 줄\n\n[B] 네.\n\n[A] 끝.\n";
  assert.deepEqual(transcriptSpeakers(text), ["A", "B"]);
  const named = renameSpeakers(text, { A: "재박", B: "민수" });
  assert.equal(named, "# 회의\n\n(whisperX 자동 전사)\n\n[재박] 안녕. [B]라고 부를게요.\n둘째 줄\n\n[민수] 네.\n\n[재박] 끝.\n");
  assert.deepEqual(transcriptSpeakers(named), ["재박", "민수"]);
  assert.equal(renameSpeakers(named, { 재박: "민수", 민수: "재박" }), "# 회의\n\n(whisperX 자동 전사)\n\n[민수] 안녕. [B]라고 부를게요.\n둘째 줄\n\n[재박] 네.\n\n[민수] 끝.\n");
});

test("diarizerStatus: no whisperX → unavailable; missing until both package and models are there", async () => {
  const { python, site } = await venv();
  const dir = await mkdtemp(join(tmpdir(), "zv-models-"));
  assert.equal(diarizerStatus(null, dir).state, "unavailable");
  assert.equal(diarizerStatus(python, dir).state, "missing");
  assert.equal(diarizerStatus(python, dir).downloadMb, 33);
  mkdirSync(join(site, "sherpa_onnx"));
  writeFileSync(join(dir, "segmentation.onnx"), "");
  assert.equal(diarizerStatus(python, dir).state, "missing");
  writeFileSync(join(dir, "embedding.onnx"), "");
  assert.equal(diarizerStatus(python, dir).state, "ready");
});

test("installDiarizer pins sherpa-onnx with uv, verifies and unpacks both models", async () => {
  const { python, site } = await venv();
  const dir = await mkdtemp(join(tmpdir(), "zv-models-"));
  const { assets, fetchImpl, fetched } = await fakeAssets();
  const ran: string[][] = [];
  await installDiarizer({
    python, dir, uv: "/bin/uv", assets, fetchImpl,
    run: async (cmd, args) => {
      ran.push([cmd, ...args]);
      mkdirSync(join(site, "sherpa_onnx"));
    },
  });
  assert.deepEqual(ran, [["/bin/uv", "pip", "install", "--python", python, `sherpa-onnx==${SHERPA_ONNX_VERSION}`]]);
  assert.deepEqual(fetched, ["https://example/seg.tar.bz2", "https://example/emb.onnx"]);
  assert.equal(readFileSync(join(dir, "segmentation.onnx"), "utf8"), "SEG");
  assert.equal(readFileSync(join(dir, "embedding.onnx"), "utf8"), "EMBEDDING");
  assert.ok(existsSync(join(dir, "LICENSE-pyannote-segmentation-3.0")));
  assert.match(readFileSync(join(dir, "VERSION"), "utf8"), /sherpa-onnx 2\.0\.1/);
  assert.ok(!existsSync(join(dir, "download")), "the download folder is cleaned up");
  assert.equal(diarizerStatus(python, dir).state, "ready");

  // a second run has nothing to do
  ran.length = 0;
  fetched.length = 0;
  await installDiarizer({ python, dir, uv: "/bin/uv", assets, fetchImpl, run: async (c, a) => void ran.push([c, ...a]) });
  assert.deepEqual([ran, fetched], [[], []]);
});

test("ensureDiarizer shares one install between callers; a failed download is reported, not thrown", async () => {
  const { python, site } = await venv();
  const dir = await mkdtemp(join(tmpdir(), "zv-models-"));
  const { assets, fetchImpl } = await fakeAssets();
  let installs = 0;
  const run = async () => {
    installs++;
    await new Promise((r) => setTimeout(r, 20));
    mkdirSync(join(site, "sherpa_onnx"), { recursive: true });
  };
  const a = ensureDiarizer(python, { dir, uv: "/bin/uv", assets, fetchImpl, run });
  assert.equal(diarizerStatus(python, dir).state, "installing");
  const b = ensureDiarizer(python, { dir, uv: "/bin/uv", assets, fetchImpl, run });
  assert.deepEqual(await Promise.all([a, b]), [true, true]);
  assert.equal(installs, 1);

  const other = await venv();
  const empty = await mkdtemp(join(tmpdir(), "zv-models-"));
  const broken = { ...assets, embedding: { ...assets.embedding, url: "https://example/missing.onnx" } };
  const ok = await ensureDiarizer(other.python, { dir: empty, uv: "/bin/uv", assets: broken, fetchImpl, run: async () => void mkdirSync(join(other.site, "sherpa_onnx"), { recursive: true }) });
  assert.equal(ok, false);
  const st = diarizerStatus(other.python, empty);
  assert.equal(st.state, "failed");
  assert.match(st.error ?? "", /HTTP 404/);
});
