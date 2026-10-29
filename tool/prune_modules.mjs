// Drops native files the packaged server will never load.
// onnxruntime-node ships every OS and CPU in one npm package; its loader only
// opens bin/napi-v6/<platform>/<arch>. tesseract.js on Node uses an LSTM build
// and falls back from relaxed-SIMD to SIMD to plain, so the non-LSTM cores go.

import { existsSync, readdirSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";

/** True for a tesseract.js-core file Node never requires (the legacy non-LSTM cores). */
export function unusedTesseractFile(name) {
  return name.startsWith("tesseract-core") && !name.includes("lstm");
}

function findDirs(root, name, out = []) {
  if (!existsSync(root)) return out;
  for (const entry of readdirSync(root)) {
    if (entry === ".bin") continue;
    const path = join(root, entry);
    let st;
    try {
      st = statSync(path);
    } catch {
      continue;
    }
    if (!st.isDirectory()) continue;
    if (entry === name) out.push(path);
    else findDirs(path, name, out);
  }
  return out;
}

function pruneOnnx(pkg, platform, arch) {
  const bin = join(pkg, "bin");
  if (!existsSync(bin)) return;
  for (const napi of readdirSync(bin)) {
    const napiDir = join(bin, napi);
    if (napi !== "napi-v6") {
      rmSync(napiDir, { recursive: true, force: true });
      continue;
    }
    for (const plat of readdirSync(napiDir)) {
      const platDir = join(napiDir, plat);
      if (plat !== platform) {
        rmSync(platDir, { recursive: true, force: true });
        continue;
      }
      for (const cpu of readdirSync(platDir)) {
        if (cpu !== arch) rmSync(join(platDir, cpu), { recursive: true, force: true });
      }
    }
  }
}

function pruneTesseract(pkg) {
  for (const name of readdirSync(pkg)) {
    if (unusedTesseractFile(name)) rmSync(join(pkg, name), { force: true });
  }
}

/** Removes other platforms' binaries under [root] (`node_modules`). */
export function prunePayload(root, platform, arch) {
  for (const pkg of findDirs(root, "onnxruntime-node")) pruneOnnx(pkg, platform, arch);
  for (const pkg of findDirs(root, "tesseract.js-core")) pruneTesseract(pkg);
}

const isMain = process.argv[1] && process.argv[1].endsWith("prune_modules.mjs");
if (isMain) {
  const [root, platform, arch] = process.argv.slice(2);
  if (!root || !platform || !arch) {
    console.error("usage: node prune_modules.mjs <node_modules> <darwin|linux|win32> <arm64|x64>");
    process.exit(1);
  }
  prunePayload(root, platform, arch);
}
