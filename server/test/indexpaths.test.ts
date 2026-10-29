import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

process.env.ZAEVIS_HOME = await mkdtemp(join(tmpdir(), "zv-index-state-"));
const { displayPath } = await import("../src/autorag.ts");
const { readIndexedFile, sourcePrefixes, syncSearchPaths } = await import("../src/indexpaths.ts");

test("index paths: two worklog folders keep distinct hit paths, and searchPaths gains the extra folder", async () => {
  const root = await mkdtemp(join(tmpdir(), "zv-index-"));
  const worklog = join(root, "worklog");
  const memory = join(root, "notes", "worklog");
  await mkdir(join(worklog, "log"), { recursive: true });
  await mkdir(join(memory, "log"), { recursive: true });
  await writeFile(join(worklog, "log", "2026-10.md"), "기록");
  await writeFile(join(memory, "log", "2026-10.md"), "메모리");
  const cfgFile = join(root, "autorag.json");
  await writeFile(cfgFile, JSON.stringify({ searchPaths: [worklog], rerank: false }));

  const prefixes = sourcePrefixes([worklog, memory]);
  const memoryPrefix = prefixes.find((p) => p.root === memory)!.prefix;
  assert.equal(displayPath(`${memoryPrefix}/log/2026-10.md`, [worklog, memory]), join(memory, "log", "2026-10.md"));
  assert.equal(displayPath(`${prefixes.find((p) => p.root === worklog)!.prefix}/log/2026-10.md`, [worklog, memory]), "log/2026-10.md");

  const hit = readIndexedFile(join(memory, "log", "2026-10.md"), [worklog, memory]);
  assert.equal(hit?.markdown, "메모리");
  assert.equal(readIndexedFile(join(root, "log", "2026-10.md"), [worklog, memory]), null);

  assert.equal(syncSearchPaths({ worklogDir: worklog, memoryPaths: [memory], autoragConfig: cfgFile }), true);
  const saved = JSON.parse(await readFile(cfgFile, "utf8")) as { searchPaths: string[]; rerank: boolean };
  assert.deepEqual(saved.searchPaths, [worklog, memory]);
  assert.equal(saved.rerank, false);
  assert.equal(syncSearchPaths({ worklogDir: worklog, memoryPaths: [memory], autoragConfig: cfgFile }), false);
});
