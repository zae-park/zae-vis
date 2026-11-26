import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { copyRedacted, findSecrets, redact, scanWorklog } from "../src/redact.ts";
import { Worklog } from "../src/worklog.ts";
import { meetingDraftBody } from "../src/asr.ts";

// 토큰 모양은 실행할 때만 붙인다 (공개 저장소 비밀 검사가 가짜 값을 잡지 않게).
const j = (...p: string[]) => p.join("");
const rep = (ch: string, n: number) => ch.repeat(n);

test("redact covers newer token shapes", () => {
  const cases: Array<[string, string]> = [
    [j("eyJ", "hbGciOiJIUzI1NiJ9", ".", "eyJ", "zdWIiOiIxMjM0NSJ9", ".", "abcdefghijKLMN"), "jwt***"],
    [j("sk_", "live_", rep("a", 24)), "stripe***"],
    [j("glpat-", rep("b", 20)), "glpat-***"],
    [j("npm_", rep("C", 36)), "npm_***"],
    [j("ya29.", rep("d", 30)), "ya29.***"],
    [j("https://hooks.slack.com/services/", "T0000/B0000/", rep("e", 24)), "services/***"],
    [j("https://discord.com/api/webhooks/123456/", rep("f", 30)), "webhooks/123456/***"],
    [j("123456789:", rep("G", 35)), "123456789:***"],
    [j("sk-or-v1-", rep("1", 40)), "sk-***"],
  ];
  for (const [secret, masked] of cases) {
    const out = redact(`값 ${secret} 끝`);
    assert.ok(out.includes(masked), `${masked} in ${out}`);
    assert.ok(!out.includes(secret), out);
  }
  const my = redact(j("mysql -u root -p", "hunter22", " db"));
  assert.equal(my, "mysql -u root -p*** db");
});

test("redact is idempotent and leaves ordinary text alone", () => {
  const once = redact(j("export API_KEY=", rep("z", 20), " token: ", "abcd1234", " https://u:", "pw123", "@h/"));
  assert.equal(redact(once), once);
  assert.deepEqual(findSecrets(once), {});
  for (const plain of ["회의 3시: 색인 누락 확인", "git push -u origin main", "token 개수 세기", "mysql -u root -p"]) assert.equal(redact(plain), plain);
});

test("findSecrets names rules without the values", () => {
  const hits = findSecrets(j("Bearer ", rep("x", 20), " and ", j("ghp_", rep("y", 30)), " password=", "abcdef"));
  assert.deepEqual(hits, { bearer: 1, github: 1, "key-value": 1 });
});

test("scanWorklog reports and, with apply, masks stored files", async () => {
  const root = await mkdtemp(join(tmpdir(), "zv-redact-"));
  const secret = j("ghp_", rep("q", 30));
  await mkdir(join(root, "sources", "shell-history"), { recursive: true });
  await mkdir(join(root, "processed", "audio"), { recursive: true });
  await writeFile(join(root, "sources", "shell-history", "2026-11-01.md"), `- \`curl -H 'x' ${secret}\`\n`);
  await writeFile(join(root, "processed", "audio", "a.txt"), secret); // audio 폴더는 건너뜀
  await writeFile(join(root, "clean.md"), "평범한 기록\n");
  const dry = await scanWorklog(root);
  assert.deepEqual(dry, [{ file: "sources/shell-history/2026-11-01.md", rules: { github: 1 } }]);
  assert.ok((await readFile(join(root, "sources", "shell-history", "2026-11-01.md"), "utf8")).includes(secret));
  await scanWorklog(root, { apply: true });
  assert.ok(!(await readFile(join(root, "sources", "shell-history", "2026-11-01.md"), "utf8")).includes(secret));
  assert.deepEqual(await scanWorklog(root), []);
});

test("write paths that used to skip masking now mask", async () => {
  const root = await mkdtemp(join(tmpdir(), "zv-redact-w-"));
  const secret = j("sk-proj-", rep("w", 24));
  const wl = new Worklog(root);
  const { line } = await wl.appendLog({ text: `키 바꿈 OPENAI_API_KEY=${secret}`, tags: [], projects: [] });
  assert.ok(!line.includes(secret), line);
  const file = await wl.saveTranscript("memo", `말하길 ${secret}`);
  assert.ok(!(await readFile(file, "utf8")).includes(secret));
  assert.ok(!meetingDraftBody("m", `토큰 ${secret}`).includes(secret));
  const src = join(root, "in.txt");
  await writeFile(src, `회의 중 ${secret}`);
  await copyRedacted(src, join(root, "out.txt"));
  assert.ok(!(await readFile(join(root, "out.txt"), "utf8")).includes(secret));
});

test("prompts are masked before they reach an agent", async () => {
  const { generateText } = await import("../src/ask.ts");
  const secret = j("xoxb-", rep("9", 20));
  let sent = "";
  const exec = async (_bin: string, args: string[]) => {
    sent = args.join(" ");
    return { ok: true, stdout: "답", stderr: "" };
  };
  const agent = { id: "claude", title: "Claude Code", bin: "/bin/claude", installed: true } as never;
  const out = await generateText(agent, `발췌 [1] 슬랙: ${secret}`, "", tmpdir(), { exec: exec as never });
  assert.equal(out, "답");
  assert.ok(sent.includes("xox-***") && !sent.includes(secret), sent);
});
