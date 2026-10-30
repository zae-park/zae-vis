import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import type { AppConfig } from "../src/config.ts";

process.env.ZAEVIS_HOME = await mkdtemp(join(tmpdir(), "zv-col-"));
const { addCustomSource } = await import("../src/config.ts");
const { collect } = await import("../src/sources/index.ts");

test("collect tells the app which source is running and when it finishes", async () => {
  const work = await mkdtemp(join(tmpdir(), "zv-col-work-"));
  addCustomSource({ name: "ping", command: "printf ping-ok", description: "ping" });
  const seen: string[] = [];
  const cfg = { worklogDir: work } as AppConfig;
  const report = await collect(cfg, {
    only: ["ping"],
    onProgress: (p) => seen.push(p.steps.map((s) => `${s.name}:${s.state}:${s.line ?? ""}`).join("|")),
  });
  assert.equal(report[0]?.ok, true);
  assert.ok(seen.some((s) => s.startsWith("ping:running")));
  assert.match(seen.at(-1) ?? "", /^ping:done/);
});
