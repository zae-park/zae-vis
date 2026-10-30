import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

process.env.ZAEVIS_HOME = await mkdtemp(join(tmpdir(), "zv-hf-"));
const { hfLoginSettled, hfStatus, logoutHf, startHfLogin, tokenForDiarize } = await import("../src/hf.ts");

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

test("Hugging Face login stores a token from the browser flow and never returns it", async () => {
  let polls = 0;
  const fetchImpl: typeof fetch = async (input) => {
    const url = String(input);
    if (url.endsWith("/oauth/device")) {
      return json({ device_code: "secret-device", user_code: "ABCD-EFGH", verification_uri: "https://hf.co/oauth/device", verification_uri_complete: "https://hf.co/oauth/device?user_code=ABCD-EFGH", interval: 1, expires_in: 60 });
    }
    if (url.endsWith("/oauth/token")) {
      polls++;
      if (polls === 1) return json({ error: "authorization_pending" }, 400);
      return json({ access_token: "hf_test_token_value", refresh_token: "refresh", expires_in: 3600 });
    }
    if (url.includes("/whoami")) return json({ name: "zaepark" });
    if (url.includes("speaker-diarization")) return json({ error: "restricted" }, 403);
    if (url.includes("/models/")) return json({ id: "ok" });
    return json({ error: "no" }, 404);
  };

  const started = await startHfLogin(fetchImpl, async () => {});
  assert.equal(started.login?.userCode, "ABCD-EFGH");
  assert.equal(JSON.stringify(started).includes("hf_test_token_value"), false);
  assert.equal(JSON.stringify(started).includes("secret-device"), false);
  await hfLoginSettled();

  const st = hfStatus();
  assert.equal(st.loggedIn, true);
  assert.equal(st.username, "zaepark");
  assert.equal(st.login, null);
  assert.deepEqual(st.accept, ["pyannote/speaker-diarization-3.1"]);
  assert.equal(JSON.stringify(st).includes("hf_test_token_value"), false);
  assert.equal(await tokenForDiarize(fetchImpl), null, "diarization stays off until the model page is accepted");

  assert.equal(logoutHf().loggedIn, false);
});
