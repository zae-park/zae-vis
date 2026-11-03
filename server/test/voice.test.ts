import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { VoiceTranscriber } from "../src/voice.ts";

const python = (() => {
  for (const p of ["python3", "python"]) {
    try {
      execFileSync(p, ["-c", "print(1)"]);
      return p;
    } catch {}
  }
  return null;
})();

test("voice: one daemon answers each request by id, then idles out", { skip: !python || process.platform === "win32" }, async () => {
  const dir = await mkdtemp(join(tmpdir(), "zv-voice-"));
  const script = join(dir, "fake_daemon.py");
  // the daemon's protocol: argv model threads, a ready line, then one JSON reply per request line
  await writeFile(script, [
    "import json, sys",
    "print(json.dumps({'ready': True}), flush=True)",
    "for line in sys.stdin:",
    "    r = json.loads(line)",
    "    if r['path'].endswith('bad.wav'):",
    "        print(json.dumps({'id': r['id'], 'error': 'cannot read'}), flush=True)",
    "    else:",
    "        print(json.dumps({'id': r['id'], 'text': f\"{sys.argv[1]}:{r['language']}:{r['path'][-6:]}\"}, ensure_ascii=False), flush=True)",
  ].join("\n"));
  const v = new VoiceTranscriber({ python: () => python, model: () => "tiny", script, idleMs: 300 });
  const [a, b] = await Promise.all([v.transcribe("/x/a1.wav", "ko"), v.transcribe("/x/b2.wav")]);
  assert.equal(a, "tiny:ko:a1.wav");
  assert.equal(b, "tiny:None:b2.wav", "no language: whisper detects it");
  await assert.rejects(v.transcribe("/x/bad.wav"), /음성 인식 실패: cannot read/);
  assert.equal(v.running, true);
  await new Promise((r) => setTimeout(r, 600));
  assert.equal(v.running, false, "the model leaves memory when idle");
  assert.equal(await v.transcribe("/x/c3.wav", "en"), "tiny:en:c3.wav", "and comes back on the next command");
  v.stop();
});

test("voice: without whisperX it says what to install", async () => {
  const v = new VoiceTranscriber({ python: () => null });
  await assert.rejects(v.transcribe("/x/a.wav"), /whisperX가 필요합니다/);
});
