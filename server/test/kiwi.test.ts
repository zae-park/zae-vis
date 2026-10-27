import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { createReadStream, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Readable } from "node:stream";
import { test } from "node:test";

process.env.ZAEVIS_HOME = await mkdtemp(join(tmpdir(), "zv-kiwi-"));
const { KIWI_ASSETS, KIWI_VERSION, TokenizerGate, installKiwi, kiwiEnv, kiwiEnvKey, lexicalLanguage, libraryAsset, probeKiwi, releaseUrl } = await import("../src/kiwi.ts");
const { loadState } = await import("../src/config.ts");

const HOME = "/Users/me";
const mac = (exists: string[], env: NodeJS.ProcessEnv = {}) => probeKiwi({ platform: "darwin", arch: "arm64", home: HOME, env, dir: "/state/ext/kiwi", exists: (p) => exists.includes(p) });

test("kiwi probe: nothing found → not installed, with the platform asset and size for the UI", () => {
  const s = mac([]);
  assert.equal(s.installed, false);
  assert.equal(s.library, null);
  assert.equal(s.source, null);
  assert.equal(s.asset, `kiwi_mac_arm64_v${KIWI_VERSION}.tgz`);
  assert.equal(s.downloadMb, 129);
  assert.equal(s.dir, "/state/ext/kiwi");
  assert.deepEqual(kiwiEnv(s), {}, "nothing to hand to the child");
  assert.equal(kiwiEnvKey(s), "");
});

test("kiwi probe: zaevis's own install wins over ~/.local/kiwi and the system folders", () => {
  const ours = ["/state/ext/kiwi/lib/libkiwi.dylib", "/state/ext/kiwi/models/cong/base"];
  const user = [`${HOME}/.local/kiwi/lib/libkiwi.dylib`, `${HOME}/.local/kiwi/models/cong/base`];
  const system = ["/opt/homebrew/lib/libkiwi.dylib", "/opt/homebrew/models/cong/base"];
  const s = mac([...ours, ...user, ...system]);
  assert.equal(s.installed, true);
  assert.equal(s.source, "zaevis");
  assert.deepEqual(kiwiEnv(s), { KIWI_LIBRARY_PATH: ours[0], KIWI_MODEL_PATH: ours[1] });
  assert.equal(mac([...user, ...system]).source, "user");
  assert.equal(mac(system).source, "system");
  assert.deepEqual(kiwiEnv(mac(system)), { KIWI_LIBRARY_PATH: system[0], KIWI_MODEL_PATH: system[1] }, "a system install is still passed explicitly (kiwi-rs would find it, AutoRAG's probe too)");
  const half = mac([ours[0]]);
  assert.equal(half.installed, false, "library without the model is not enough");
  assert.equal(half.library, ours[0]);
  assert.equal(half.model, null);
});

test("kiwi probe: explicit KIWI_* paths are authoritative, even when they are missing", () => {
  const ours = ["/state/ext/kiwi/lib/libkiwi.dylib", "/state/ext/kiwi/models/cong/base"];
  const s = mac([...ours, "/x/lib.dylib", "/x/model"], { KIWI_LIBRARY_PATH: "/x/lib.dylib", KIWI_MODEL_PATH: "/x/model" });
  assert.equal(s.source, "env");
  assert.equal(s.installed, true);
  assert.deepEqual(kiwiEnv(s), {}, "the user's own variables reach the child untouched");
  const missing = mac(ours, { KIWI_LIBRARY_PATH: "/gone.dylib" });
  assert.equal(missing.installed, false, "a wrong explicit path hides the working install, as it does for kiwi-rs");
  assert.equal(mac(ours, { KIWI_LIBRARY_PATH: "" }).installed, true, "an empty variable is ignored");
});

test("kiwi probe: platform file names and asset table", () => {
  const win = probeKiwi({ platform: "win32", arch: "x64", home: "C:\\Users\\me", env: { LOCALAPPDATA: "C:\\Users\\me\\AppData\\Local" }, dir: "C:\\st\\ext\\kiwi", exists: (p) => p.includes("AppData") });
  assert.equal(win.library, join("C:\\Users\\me\\AppData\\Local", "kiwi", "lib", "kiwi.dll"));
  assert.equal(win.asset, `kiwi_win_x64_v${KIWI_VERSION}.zip`);
  const linux = probeKiwi({ platform: "linux", arch: "arm64", home: "/home/me", env: {}, dir: "/s", exists: (p) => p.startsWith("/usr/lib") || p.startsWith("/usr/share") });
  assert.equal(linux.library, "/usr/lib/libkiwi.so");
  assert.equal(linux.model, "/usr/share/kiwi/models/cong/base");
  assert.equal(linux.source, "system");
  assert.equal(libraryAsset("linux", "ia32"), null, "no release → the UI offers the manual route instead of a button");
  assert.equal(releaseUrl(KIWI_ASSETS.model), `https://github.com/bab2min/Kiwi/releases/download/v${KIWI_VERSION}/kiwi_model_v${KIWI_VERSION}_base.tgz`);
  for (const a of [...Object.values(KIWI_ASSETS.library), KIWI_ASSETS.model]) assert.match(a.sha256, /^[0-9a-f]{64}$/, a.name);
});

/** A tiny release pair: lib/ with the dylib + a static archive, models/cong/base with the model files. */
function fixtureRelease(root: string): { library: { name: string; sha256: string; bytes: number }; model: { name: string; sha256: string; bytes: number }; url: (a: { name: string }) => string } {
  const src = join(root, "src");
  mkdirSync(join(src, "lib"), { recursive: true });
  mkdirSync(join(src, "models", "cong", "base"), { recursive: true });
  writeFileSync(join(src, "lib", "libkiwi.dylib"), "not really a dylib");
  writeFileSync(join(src, "lib", "libkiwi_static.a"), "x".repeat(2000));
  writeFileSync(join(src, "include.h"), "// headers are not extracted");
  writeFileSync(join(src, "models", "cong", "base", "sj.morph"), "morph");
  writeFileSync(join(src, "models", "cong", "base", "combiningRule.txt"), "rules");
  const libTgz = join(root, "lib.tgz");
  const modelTgz = join(root, "model.tgz");
  assert.equal(spawnSync("tar", ["-czf", libTgz, "-C", src, "lib", "include.h"]).status, 0);
  assert.equal(spawnSync("tar", ["-czf", modelTgz, "-C", src, "models"]).status, 0);
  const asset = (file: string, name: string) => ({ name, sha256: createHash("sha256").update(readFileSync(file)).digest("hex"), bytes: readFileSync(file).length });
  return { library: asset(libTgz, "lib.tgz"), model: asset(modelTgz, "model.tgz"), url: (a) => `fixture://${a.name}` };
}

const fileFetch = (root: string, bad: string[] = []): typeof fetch => (async (url: string | URL | Request) => {
  const name = String(url).replace("fixture://", "");
  const f = join(root, bad.includes(name) ? "src/include.h" : name);
  return new Response(Readable.toWeb(createReadStream(f)) as ReadableStream, { status: 200 });
}) as typeof fetch;

test("kiwi install: downloads the pair with checksums, keeps only lib/ and models/, writes VERSION, is idempotent", async () => {
  const root = await mkdtemp(join(tmpdir(), "zv-kiwi-rel-"));
  const assets = fixtureRelease(root);
  const dir = join(root, "ext", "kiwi");
  const log: string[] = [];
  const s = await installKiwi({ dir, platform: "darwin", arch: "arm64", assets, fetchImpl: fileFetch(root), log: (l) => log.push(l) });
  assert.equal(s.installed, true);
  assert.equal(s.source, "zaevis");
  assert.equal(s.version, KIWI_VERSION);
  assert.equal(s.library, join(dir, "lib", "libkiwi.dylib"));
  assert.equal(s.model, join(dir, "models", "cong", "base"));
  assert.equal(readFileSync(join(dir, "models", "cong", "base", "sj.morph"), "utf8"), "morph");
  assert.equal(existsSync(join(dir, "lib", "libkiwi_static.a")), false, "static archive dropped");
  assert.equal(existsSync(join(dir, "include.h")), false, "headers never extracted");
  assert.equal(existsSync(join(dir, "downloads")), false, "archives removed after unpacking");
  assert.equal(readFileSync(join(dir, "VERSION"), "utf8").trim(), KIWI_VERSION);
  assert.ok(log.some((l) => l.includes("설치 완료")), log.join("\n"));
  log.length = 0;
  await installKiwi({ dir, platform: "darwin", arch: "arm64", assets, fetchImpl: fileFetch(root), log: (l) => log.push(l) });
  assert.ok(log.some((l) => l.includes("이미 설치됨")), "same version → nothing downloaded again");
  assert.equal(probeKiwi({ dir, platform: "darwin", arch: "arm64", env: {}, home: "/nowhere" }).installed, true);
});

test("kiwi install: a checksum mismatch leaves nothing behind", async () => {
  const root = await mkdtemp(join(tmpdir(), "zv-kiwi-bad-"));
  const assets = fixtureRelease(root);
  const dir = join(root, "ext", "kiwi");
  await assert.rejects(installKiwi({ dir, platform: "darwin", arch: "arm64", assets, fetchImpl: fileFetch(root, ["model.tgz"]) }), /체크섬 불일치/);
  assert.equal(existsSync(join(dir, "models")), false);
  assert.equal(existsSync(join(dir, "VERSION")), false);
  assert.equal(existsSync(join(dir, "downloads", "model.tgz")), false, "the bad download is deleted");
  assert.equal(existsSync(join(dir, "downloads", "model.tgz.part")), false);
});

test("kiwi install: no release for the platform → a clear error with the manual route", async () => {
  await assert.rejects(installKiwi({ dir: join(process.env.ZAEVIS_HOME!, "x"), platform: "linux", arch: "ia32" }), /linux-ia32.*KIWI_LIBRARY_PATH/s);
});

test("tokenizer gate: Kiwi appearing restarts the child and owes a rebuild until a forced refresh succeeds", async () => {
  const home = process.env.ZAEVIS_HOME!;
  const ws = join(home, "ws");
  mkdirSync(join(ws, ".autorag", "minsync", ".minsync"), { recursive: true });
  const autoragConfig = join(home, "autorag-config.json");
  writeFileSync(autoragConfig, JSON.stringify({ workspacePath: ws }));
  assert.equal(lexicalLanguage(autoragConfig), null, "no index yet");
  writeFileSync(join(ws, ".autorag", "minsync", ".minsync", "config.toml"), '[chunker]\nid = "recursive"\n\n[lexical]\nlanguage = "simple"\n\n[sync]\nbatch_files = 25\n');
  assert.equal(lexicalLanguage(autoragConfig), "simple");

  let installed = false;
  const restarts: number[] = [];
  const probe = () => ({ ...probeKiwi({ platform: "darwin", arch: "arm64", home: "/nowhere", env: {}, dir: "/k", exists: () => installed }), installed, library: installed ? "/k/lib/libkiwi.dylib" : null, model: installed ? "/k/models/cong/base" : null });
  const gate = new TokenizerGate({ autoragConfig, restart: async () => void restarts.push(1), probe });
  let t = await gate.sync(true);
  assert.equal(t.active, "whitespace");
  assert.equal(t.needsReindex, false, "nothing to rebuild with: Kiwi is not here");
  assert.deepEqual(gate.env(), {});
  assert.equal(restarts.length, 0);

  installed = true;
  t = await gate.sync(false);
  assert.equal(restarts.length, 0, "a running refresh keeps its child");
  t = await gate.sync(true);
  assert.equal(restarts.length, 1, "the child restarts so the next refresh gets KIWI_* in its env");
  assert.deepEqual(gate.env(), { KIWI_LIBRARY_PATH: "/k/lib/libkiwi.dylib", KIWI_MODEL_PATH: "/k/models/cong/base" });
  assert.equal(t.needsReindex, true);
  assert.equal(loadState().kiwiReindexPending, true, "remembered across server restarts");
  assert.equal((await gate.sync(true)).needsReindex, true);
  assert.equal(restarts.length, 1, "unchanged paths → no second restart");

  // AutoRAG's next refresh writes `multilingual`, but an incremental one keeps the old chunks' tokens
  writeFileSync(join(ws, ".autorag", "minsync", ".minsync", "config.toml"), '[lexical]\nlanguage = "multilingual"\n');
  gate.refreshed(false, true);
  t = gate.status();
  assert.equal(t.active, "multilingual");
  assert.equal(t.needsReindex, true, "only a rebuild from scratch settles it");
  gate.refreshed(true, false);
  assert.equal(gate.status().needsReindex, true, "a failed rebuild does not count");
  gate.refreshed(true, true);
  assert.equal(gate.status().needsReindex, false);
  assert.equal(loadState().kiwiReindexPending, false);

  // a new server finding Kiwi next to an index built on whitespace owes the rebuild from the start
  writeFileSync(join(ws, ".autorag", "minsync", ".minsync", "config.toml"), '[lexical]\nlanguage = "simple"\n');
  const fresh = new TokenizerGate({ autoragConfig, restart: async () => {}, probe });
  assert.equal(fresh.status().needsReindex, true);
  assert.equal(loadState().kiwiReindexPending, true);
});
