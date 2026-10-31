import assert from "node:assert/strict";
import { test } from "node:test";
import { foldWhisperLine, transcribeLaunchArgs, whisperStatusLine, type WhisperView } from "../src/transcribe.ts";

const start: WhisperView = { label: "모델 불러오는 중", fraction: null };

test("whisperX progress lines become a phase and a fraction", () => {
  const heard = foldWhisperLine(start, "2026-10-30 17:00:00 - whisperx.transcribe - INFO - Performing transcription...");
  assert.deepEqual(heard, { label: "음성 인식", fraction: null });
  const mid = foldWhisperLine(heard!, "Progress: 45.00%...");
  assert.deepEqual(mid, { label: "음성 인식", fraction: 0.45 });
  assert.equal(whisperStatusLine(mid!), "음성 인식 45%");
  const align = foldWhisperLine(mid!, "INFO - Performing alignment...");
  assert.deepEqual(align, { label: "말 시간에 맞추는 중", fraction: null });
  const speakers = foldWhisperLine(align!, "Performing diarization...");
  assert.equal(speakers?.label, "말한 사람 구분 중");
  assert.equal(speakers?.fraction, null);
  assert.equal(foldWhisperLine(mid!, "Transcript: [0.0 --> 1.2] 안녕"), null);
  assert.equal(foldWhisperLine(start, "Progress: 140%")?.fraction, 1);
});

test("the fast pass uses every CPU core and leaves speakers and alignment out", () => {
  const args = transcribeLaunchArgs("/tmp/a.wav", "/tmp/out", { threads: 14 });
  assert.equal(args.includes("--diarize"), false);
  assert.equal(args.includes("--hf_token"), false);
  assert.ok(args.includes("--no_align"));
  assert.deepEqual(args.slice(args.indexOf("--threads"), args.indexOf("--threads") + 2), ["--threads", "14"]);
  assert.deepEqual(args.slice(args.indexOf("--vad_method"), args.indexOf("--vad_method") + 2), ["--vad_method", "silero"]);
  assert.deepEqual(args.slice(args.indexOf("--device"), args.indexOf("--device") + 2), ["--device", "cpu"]);
});
