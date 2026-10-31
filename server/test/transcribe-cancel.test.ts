import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { chmod, mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { TranscribeQueue } from "../src/transcribe.ts";

async function waitFor(pred: () => boolean, ms = 4000): Promise<boolean> {
  const end = Date.now() + ms;
  while (!pred() && Date.now() < end) await new Promise((r) => setTimeout(r, 20));
  return pred();
}

test("cancel drops a queued transcription before whisperX starts", async () => {
  const dir = await mkdtemp(join(tmpdir(), "zv-cancel-q-"));
  try {
    const audio = join(dir, "note.wav");
    await writeFile(audio, "wav");
    const q = new TranscribeQueue();
    let finished = 0;
    q.onDone = () => { finished++; };
    q.enqueue(audio, join(dir, "work"), { whisperxBin: join(dir, "missing-whisperx") });
    assert.equal(q.cancel("note.wav"), true);
    assert.equal(await waitFor(() => q.jobs[0]?.state === "cancelled"), true);
    assert.equal(q.jobs[0]?.line, "취소했습니다");
    assert.equal(q.jobs[0]?.state, "cancelled");
    assert.equal(existsSync(audio), true);
    assert.equal(finished, 0);
    assert.equal(q.cancel("note.wav"), false);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("cancel kills a running transcription and leaves the audio in place", async () => {
  const dir = await mkdtemp(join(tmpdir(), "zv-cancel-run-"));
  try {
    const bin = join(dir, "whisperx");
    await writeFile(bin, "#!/bin/bash\ntrap 'exit 0' TERM INT\nwhile true; do sleep 0.2; done\n");
    await chmod(bin, 0o755);
    const audio = join(dir, "note.wav");
    await writeFile(audio, "wav");
    const work = join(dir, "work");
    await mkdir(work);
    const q = new TranscribeQueue();
    let finished = 0;
    q.onDone = () => { finished++; };
    q.enqueue(audio, work, { whisperxBin: bin });
    assert.equal(await waitFor(() => q.jobs[0]?.state === "running"), true);
    assert.equal(q.cancel(audio), true);
    assert.equal(q.jobs[0]?.line, "취소하는 중");
    assert.equal(await waitFor(() => q.jobs[0]?.state === "cancelled"), true);
    assert.equal(q.jobs[0]?.line, "취소했습니다");
    assert.equal(q.jobs[0]?.error, undefined);
    assert.equal(existsSync(audio), true);
    assert.equal(existsSync(join(work, "inbox", "transcripts")), false);
    assert.equal(finished, 0);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
