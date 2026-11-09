import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { readdir } from "node:fs/promises";
import {
  chunkerFlush,
  chunkerPush,
  createChunker,
  frameRms,
  meetingDraftBody,
  meetingDraftRelPath,
  pcmDurationMs,
  speechBytes,
  POLICY,
  wavFromPcm,
  AsrHub,
  AsrSession,
  DecodeQueue,
} from "../src/asr.ts";

function loudFrame(): Buffer {
  const loud = Buffer.alloc(960);
  for (let i = 0; i < 480; i++) loud.writeInt16LE(12000, i * 2);
  return loud;
}
const quietFrame = () => Buffer.alloc(960);

test("asr: frameRms is 0 for silence and higher for a tone", () => {
  assert.equal(frameRms(Buffer.alloc(960)), 0);
  assert.ok(frameRms(loudFrame()) > 0.3);
});

test("asr: wavFromPcm has a RIFF header and the payload length", () => {
  const pcm = Buffer.alloc(3200);
  const wav = wavFromPcm(pcm);
  assert.equal(wav.toString("ascii", 0, 4), "RIFF");
  assert.equal(wav.length, 44 + pcm.length);
  assert.equal(wav.readUInt32LE(40), pcm.length);
});

test("asr: chunker emits end after speech then silence", () => {
  const policy = { ...POLICY.live, speechRms: 0.05, silenceMs: 90 };
  const st = createChunker();
  for (let i = 0; i < 5; i++) assert.equal(chunkerPush(st, loudFrame(), policy).kind, "none");
  assert.equal(st.inSpeech, true);
  let ended = false;
  for (let i = 0; i < 10; i++) {
    const t = chunkerPush(st, quietFrame(), policy);
    if (t.kind === "end") {
      ended = true;
      assert.ok(speechBytes(st) === 0);
      assert.ok(t.pcm.length > 0);
      break;
    }
  }
  assert.equal(ended, true);
});

test("asr: chunkerFlush returns leftover speech on stop", () => {
  const policy = { ...POLICY.meeting, speechRms: 0.05 };
  const st = createChunker();
  for (let i = 0; i < 8; i++) chunkerPush(st, loudFrame(), policy);
  const flush = chunkerFlush(st);
  assert.equal(flush.kind, "end");
  assert.ok(pcmDurationMs(flush.kind === "end" ? flush.pcm.length : 0) > 100);
});

test("asr: long speech does not quadratic-blow memory via speechBytes growth", () => {
  // 5 seconds of loud frames; speechBytes must stay linear with speechMs
  const policy = { ...POLICY.meeting, speechRms: 0.05, maxSpeechMs: 60_000 };
  const st = createChunker();
  const frames = Math.ceil(5000 / 30);
  for (let i = 0; i < frames; i++) chunkerPush(st, loudFrame(), policy);
  const bytes = speechBytes(st);
  const expected = frames * 960;
  assert.equal(bytes, expected, `got ${bytes} want ${expected}`);
  // Frame array (not one growing Buffer): one entry per frame → O(n) concat at flush only.
  assert.equal(st.speech.length, frames);
  assert.ok(st.speech.every((f) => f.length === 960));
});

test("asr: force-window keeps overlap frames without per-frame concat", () => {
  const policy = { ...POLICY.meeting, speechRms: 0.05, maxSpeechMs: 150, overlapMs: 60, silenceMs: 10_000 };
  const st = createChunker();
  let saw = false;
  for (let i = 0; i < 20; i++) {
    const t = chunkerPush(st, loudFrame(), policy);
    if (t.kind === "speech" && t.forceWindow) {
      saw = true;
      assert.ok(t.pcm.length > 0);
      // Overlap retained as frames (or one tail buffer), still tracked by speechBytes.
      assert.ok(speechBytes(st) > 0);
      assert.ok(st.speech.length >= 1);
      break;
    }
  }
  assert.equal(saw, true);
});

test("asr: session gathers finals from a fake transcribe", async () => {
  let n = 0;
  const hub = new AsrHub({
    transcribe: async () => {
      n += 1;
      return `seg-${n}`;
    },
    maxSessions: 2,
  });
  const session = await hub.create("meeting");
  for (let i = 0; i < 10; i++) await session.pushAudio(loudFrame());
  for (let i = 0; i < 25; i++) await session.pushAudio(quietFrame());
  const stopped = await session.stop();
  hub.forget(session.id);
  assert.ok(stopped.text.includes("seg-"), `got "${stopped.text}" after ${n} decodes`);
  assert.ok(n >= 1);
  hub.stop();
});

test("asr: cancel while a slow decode runs does not throw and cleans tmp", async () => {
  let started = false;
  let finished = false;
  const hub = new AsrHub({
    transcribe: async () => {
      started = true;
      await new Promise((r) => setTimeout(r, 80));
      finished = true;
      return "late";
    },
  });
  const s = await hub.create("live");
  const tmp = (s as unknown as { tmpRoot: string }).tmpRoot;
  // start a decode without awaiting the push fully — fire and forget a push that will queue decode
  const push = s.pushAudio(Buffer.concat(Array.from({ length: 15 }, () => loudFrame())));
  // wait until decode has started
  for (let i = 0; i < 50 && !started; i++) await new Promise((r) => setTimeout(r, 5));
  assert.equal(started, true);
  await s.cancel();
  hub.forget(s.id);
  await push.catch(() => {});
  // give the late decode a moment; cancel must not leave the tmp root
  await new Promise((r) => setTimeout(r, 120));
  assert.equal(existsSync(tmp), false, "tmp root removed");
  assert.equal(s.text, "", "cancelled decode must not commit finals");
  // finished may or may not be true; the important part is no crash and cleanup
  void finished;
  hub.stop();
});

test("asr: cancel drops waiting queue work without waiting for other sessions", async () => {
  const q = new DecodeQueue();
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  let blockedRan = false;
  const blocker = q.runQueued("high", async () => {
    blockedRan = true;
    await gate;
    return "block";
  });
  let skippedRan = false;
  let aborted = false;
  const waiting = q.runQueued(
    "low",
    async () => {
      skippedRan = true;
      return "should-not-run";
    },
    () => aborted,
  );
  await new Promise((r) => setTimeout(r, 5));
  assert.equal(blockedRan, true);
  aborted = true;
  const t0 = Date.now();
  q.flushSkipped();
  const skipped = await waiting;
  assert.ok(Date.now() - t0 < 80, "cancel should not wait on the blocker");
  assert.equal(skipped, undefined);
  assert.equal(skippedRan, false);
  release();
  await blocker;
});

test("asr: cancel during queued decode does not hang or leave finals", async () => {
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  const hub = new AsrHub({
    transcribe: async () => {
      await new Promise((r) => setTimeout(r, 20));
      return "live-text";
    },
  });
  const live = await hub.create("live");
  // Hold the shared queue like a long meeting final would.
  const blocker = hub.runQueued("high", async () => {
    await gate;
  });
  // Live partial queues behind the blocker; cancel must not wait for the gate.
  const livePush = live.pushAudio(Buffer.concat(Array.from({ length: 15 }, () => loudFrame())));
  await new Promise((r) => setTimeout(r, 30));
  const t0 = Date.now();
  await live.cancel();
  assert.ok(Date.now() - t0 < 150, `live cancel waited too long (${Date.now() - t0}ms)`);
  assert.equal(live.text, "");
  release();
  await blocker;
  await livePush.catch(() => {});
  hub.forget(live.id);
  hub.stop();
});

test("asr: push after cancel throws; mid-cancel push does not throw uncaught", async () => {
  const hub = new AsrHub({
    transcribe: async () => {
      await new Promise((r) => setTimeout(r, 40));
      return "x";
    },
  });
  const s = await hub.create("live");
  const push = s.pushAudio(Buffer.concat(Array.from({ length: 15 }, () => loudFrame())));
  await s.cancel();
  await assert.doesNotReject(() => push);
  await assert.rejects(() => s.pushAudio(loudFrame()), /끝났|세션/);
  hub.forget(s.id);
  hub.stop();
});

test("asr: meeting mode does not emit partial events", async () => {
  const hub = new AsrHub({
    transcribe: async () => "meeting-bit",
    maxSessions: 2,
  });
  const s = await hub.create("meeting");
  for (let i = 0; i < 12; i++) await s.pushAudio(loudFrame());
  assert.equal(s.partial, "");
  assert.ok(s.takeEvents().every((e) => e.type === "final"));
  await s.cancel();
  hub.forget(s.id);
  hub.stop();
});

test("asr: meetingDraftRelPath uses recording stem", () => {
  assert.equal(meetingDraftRelPath("2026-11-09_1200_녹음.wav", "abc"), "inbox/transcripts/2026-11-09_1200_녹음.md");
  assert.equal(meetingDraftRelPath(undefined, "deadbeef"), "inbox/transcripts/draft-deadbeef.md");
  const body = meetingDraftBody("stem", "  hello  ");
  assert.ok(body.includes("# stem"));
  assert.ok(body.includes("hello"));
  assert.ok(body.includes("실시간 초안"));
});

test("asr: AsrSession.open cleans up tmp on cancel", async () => {
  const s = await AsrSession.open({ mode: "live", transcribe: async () => "x", queue: new DecodeQueue() });
  const tmp = (s as unknown as { tmpRoot: string }).tmpRoot;
  await s.cancel();
  assert.equal(s.closedNow, true);
  assert.equal(existsSync(tmp), false);
  // nothing left under os tmp with that name
  try {
    await readdir(tmp);
    assert.fail("tmp should be gone");
  } catch {
    /* expected */
  }
});

test("asr: hub decode prefers final (high) over partial (low) when queued together", async () => {
  const order: string[] = [];
  const hub = new AsrHub({ transcribe: async () => "" });
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  const blocker = hub.runQueued("high", async () => {
    order.push("block");
    await gate;
  });
  // While the blocker holds the queue, enqueue low then high — high must run first after release.
  const lowP = hub.runQueued("low", async () => {
    order.push("low");
  });
  const highP = hub.runQueued("high", async () => {
    order.push("high");
  });
  await new Promise((r) => setTimeout(r, 5));
  release();
  await Promise.all([blocker, lowP, highP]);
  assert.deepEqual(order, ["block", "high", "low"]);
  hub.stop();
});
