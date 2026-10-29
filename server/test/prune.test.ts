import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const { prunePayload, unusedTesseractFile } = await import("../../tool/prune_modules.mjs");

test("prune keeps this platform's ONNX binary and the LSTM tesseract cores", () => {
  const root = mkdtempSync(join(tmpdir(), "zv-prune-"));
  const ort = join(root, "onnxruntime-node", "bin", "napi-v6");
  for (const plat of ["darwin", "linux", "win32"]) {
    for (const arch of ["arm64", "x64"]) {
      const dir = join(ort, plat, arch);
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, "onnxruntime_binding.node"), "x");
    }
  }
  const tess = join(root, "tesseract.js-core");
  mkdirSync(tess);
  for (const name of ["tesseract-core.wasm.js", "tesseract-core-simd.wasm", "tesseract-core-relaxedsimd-lstm.wasm", "tesseract-core-lstm.js", "index.js"]) {
    writeFileSync(join(tess, name), "x");
  }
  assert.equal(unusedTesseractFile("tesseract-core-simd.wasm"), true);
  assert.equal(unusedTesseractFile("tesseract-core-relaxedsimd-lstm.wasm"), false);

  prunePayload(root, "darwin", "arm64");

  assert.equal(existsSync(join(ort, "darwin", "arm64", "onnxruntime_binding.node")), true);
  assert.equal(existsSync(join(ort, "darwin", "x64")), false);
  assert.equal(existsSync(join(ort, "win32")), false);
  assert.equal(existsSync(join(ort, "linux")), false);
  assert.equal(existsSync(join(tess, "tesseract-core-relaxedsimd-lstm.wasm")), true);
  assert.equal(existsSync(join(tess, "tesseract-core-lstm.js")), true);
  assert.equal(existsSync(join(tess, "index.js")), true);
  assert.equal(existsSync(join(tess, "tesseract-core.wasm.js")), false);
  assert.equal(existsSync(join(tess, "tesseract-core-simd.wasm")), false);
});
