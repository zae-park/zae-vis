import assert from "node:assert/strict";
import { chmod, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { EmbeddingDaemon, findMinsync } from "../src/embedding.ts";

// A stand-in for `minsync serve`: prints the JSON event(s) MinSync prints, then behaves as told.
async function fakeMinsync(body: string): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "zv-emb-"));
  const bin = join(dir, "minsync");
  await writeFile(bin, `#!/bin/bash\n${body}\n`);
  await chmod(bin, 0o755);
  return bin;
}

const serving = (event: string, pid = "$$") =>
  `echo '{"event":"${event}","url":"http://127.0.0.1:1","model_id":"Qwen/Qwen3-Embedding-0.6B","device":"metal","pid":'"${pid}"',"status":"ok"}'`;

test("embedding: findMinsync looks on PATH", async () => {
  const bin = await fakeMinsync("exit 0");
  assert.equal(findMinsync({ PATH: `/nonexistent:${join(bin, "..")}` }), bin);
  assert.equal(findMinsync({ PATH: "/nonexistent" }), null);
});

test("embedding: no binary → failed with a clear error, never throws", async () => {
  const d = new EmbeddingDaemon({ binary: null });
  assert.equal(d.current.state, "off");
  assert.equal(d.current.available, false);
  const s = await d.start();
  assert.equal(s.state, "failed");
  assert.match(s.error ?? "", /minsync/);
});

test("embedding: serving event → ready; stop kills the child → off", async () => {
  const bin = await fakeMinsync(`${serving("serving")}\ntrap 'exit 0' TERM\nwhile true; do sleep 0.2; done`);
  const d = new EmbeddingDaemon({ binary: bin });
  const s = await d.start();
  assert.equal(s.state, "ready");
  assert.equal(s.url, "http://127.0.0.1:1");
  assert.equal(s.model, "Qwen/Qwen3-Embedding-0.6B");
  assert.equal(s.external, false);
  assert.ok(s.pid && s.pid > 0);
  // a second start while ready is a no-op
  assert.equal((await d.start()).state, "ready");
  const stopped = await d.stop();
  assert.equal(stopped.state, "off");
  assert.equal(stopped.enabled, false);
});

test("embedding: adopted event (daemon already running) → ready + external, exit 0 keeps it ready", async () => {
  const bin = await fakeMinsync(`${serving("adopted", "4242")}\nexit 0`);
  const d = new EmbeddingDaemon({ binary: bin });
  const s = await d.start();
  assert.equal(s.state, "ready");
  assert.equal(s.external, true);
  assert.equal(s.pid, 4242);
  await new Promise((r) => setTimeout(r, 100)); // the child's exit must not flip the state
  assert.equal(d.current.state, "ready");
});

test("embedding: stop() also terminates an adopted daemon by pid", async () => {
  const { spawn } = await import("node:child_process");
  const orphan = spawn("sleep", ["30"], { stdio: "ignore" });
  const bin = await fakeMinsync(`${serving("adopted", String(orphan.pid))}\nexit 0`);
  const d = new EmbeddingDaemon({ binary: bin, healthTimeoutMs: 200 });
  assert.equal((await d.start()).pid, orphan.pid);
  await d.stop();
  await new Promise((r) => setTimeout(r, 200));
  assert.notEqual(orphan.exitCode ?? orphan.signalCode, null, "orphan should have been signalled");
});

test("embedding: exits before ready → failed with stderr tail", async () => {
  const bin = await fakeMinsync(`echo 'model download failed: no network' >&2\nexit 3`);
  const d = new EmbeddingDaemon({ binary: bin });
  const s = await d.start();
  assert.equal(s.state, "failed");
  assert.match(s.error ?? "", /code 3/);
  assert.match(s.error ?? "", /no network/);
});

test("embedding: health() turns a vanished external daemon off", async () => {
  const bin = await fakeMinsync(`${serving("adopted", "4242")}\nexit 0`);
  const d = new EmbeddingDaemon({ binary: bin, healthTimeoutMs: 300 });
  await d.start();
  const s = await d.health(); // nothing listens on port 1
  assert.equal(s.state, "off");
});
