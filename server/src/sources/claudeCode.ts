// Claude Code keeps every session as JSONL under ~/.claude/projects/<encoded-cwd>/<session>.jsonl.
// We summarise each session per day without an LLM: title, folder, requests, files changed,
// commands run and the last answer.

import { createReadStream } from "node:fs";
import { readdir, stat } from "node:fs/promises";
import { basename, join } from "node:path";
import { createInterface } from "node:readline";
import { expandHome } from "../config.ts";
import { redact } from "../redact.ts";
import { clip, dayKey, hhmm, type Source } from "./types.ts";

type Entry = Record<string, any>;

type SessionDay = {
  sessionId: string;
  title: string;
  cwd: string;
  branch: string;
  first: Date;
  last: Date;
  prompts: string[];
  /** replies[i] is the assistant's last text answer to prompts[i] ("" when it only ran tools). */
  replies: string[];
  files: Set<string>;
  commands: string[];
  lastAnswer: string;
};

const NOISE = /^(<command-|<local-command|Base directory for this skill|Caveat:|\[Request interrupted)/;

export function userText(e: Entry): string | null {
  if (e.isMeta || e.isSidechain) return null;
  const c = e.message?.content;
  let text = "";
  if (typeof c === "string") text = c;
  else if (Array.isArray(c)) {
    if (c.some((b) => b?.type === "tool_result")) return null;
    text = c.filter((b) => b?.type === "text").map((b) => String(b.text ?? "")).join("\n");
  }
  text = text.replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, "").trim();
  if (!text || NOISE.test(text)) return null;
  return text;
}

export function summarize(lines: Entry[], from: Date, to: Date): Map<string, SessionDay> {
  const days = new Map<string, SessionDay>(); // key: day
  let title = "";
  for (const e of lines) if (e.type === "ai-title" && e.aiTitle) title = String(e.aiTitle);

  for (const e of lines) {
    if (!e.timestamp || e.isSidechain) continue;
    const t = new Date(e.timestamp);
    if (Number.isNaN(t.getTime()) || t < from || t > to) continue;
    if (e.type !== "user" && e.type !== "assistant") continue;

    const day = dayKey(t);
    let s = days.get(day);
    if (!s) {
      s = { sessionId: String(e.sessionId ?? ""), title, cwd: String(e.cwd ?? ""), branch: String(e.gitBranch ?? ""), first: t, last: t, prompts: [], replies: [], files: new Set(), commands: [], lastAnswer: "" };
      days.set(day, s);
    }
    if (t < s.first) s.first = t;
    if (t > s.last) s.last = t;
    if (!s.cwd && e.cwd) s.cwd = String(e.cwd);

    if (e.type === "user") {
      const text = userText(e);
      if (text) {
        s.prompts.push(text);
        s.replies.push("");
      }
    } else {
      for (const b of (Array.isArray(e.message?.content) ? e.message.content : []) as Entry[]) {
        if (b.type === "text" && String(b.text ?? "").trim()) setReply(s, String(b.text));
        if (b.type !== "tool_use") continue;
        const input = (b.input ?? {}) as Entry;
        const file = input.file_path ?? input.notebook_path ?? input.path;
        if (/^(Edit|Write|MultiEdit|NotebookEdit)$/.test(String(b.name)) && file) s.files.add(String(file));
        if (/(^|__)(Bash|device_bash)$/.test(String(b.name)) && input.command) s.commands.push(String(input.command));
      }
    }
  }
  for (const s of days.values()) if (!s.title && s.prompts[0]) s.title = clip(s.prompts[0], 60);
  return days;
}

/** The assistant's latest text becomes the reply to the latest prompt (and the session's last answer). */
export function setReply(s: SessionDay, text: string): void {
  s.lastAnswer = text;
  if (s.replies.length) s.replies[s.replies.length - 1] = text;
}

/** One line of a reply: the first paragraph that is not a heading or a code fence, flattened. */
function replyGist(text: string, max: number): string {
  const paras = text.split(/\n\s*\n/).map((p) => p.replace(/^#+\s*/gm, "").replace(/\s+/g, " ").trim()).filter((p) => p && !p.startsWith("```"));
  return clip(paras.join(" · "), max);
}

export function renderSession(s: SessionDay, home = ""): string {
  const short = (p: string) => (home && p.startsWith(home) ? "~" + p.slice(home.length) : p);
  const out = [`## ${hhmm(s.first)}–${hhmm(s.last)} ${redact(s.title || "(제목 없음)")}`, ""];
  out.push(`- 폴더: \`${short(s.cwd) || "?"}\`${s.branch && s.branch !== "HEAD" ? ` · 브랜치 \`${s.branch}\`` : ""} · 세션 \`${s.sessionId.slice(0, 8)}\``);
  if (s.prompts.length) {
    // request → reply pairs, so the file says what came of each ask, not only what was asked
    out.push(`- 요청과 응답 (${s.prompts.length}):`);
    s.prompts.slice(0, 8).forEach((p, i) => {
      out.push(`  - 요청: ${redact(clip(p, 220))}`);
      const r = s.replies[i];
      if (r) out.push(`    응답: ${redact(replyGist(r, 400))}`);
    });
    if (s.prompts.length > 8) out.push(`  - … 외 ${s.prompts.length - 8}개`);
  }
  if (s.files.size) {
    const files = [...s.files].map(short);
    out.push(`- 수정한 파일 (${files.length}): ${files.slice(0, 15).map((f) => `\`${f}\``).join(", ")}${files.length > 15 ? " …" : ""}`);
  }
  if (s.commands.length) {
    out.push(`- 실행한 명령 (${s.commands.length}):`);
    for (const cmd of s.commands.slice(0, 10)) out.push(`  - \`${redact(clip(cmd.split("\n")[0], 160)).replace(/`/g, "'")}\``);
  }
  if (s.lastAnswer && s.prompts.length > 8) out.push(`- 마지막 응답: ${redact(replyGist(s.lastAnswer, 400))}`);
  return out.join("\n");
}

export type { SessionDay };

export async function readJsonl(file: string): Promise<Entry[]> {
  const out: Entry[] = [];
  const rl = createInterface({ input: createReadStream(file, "utf8"), crlfDelay: Infinity });
  for await (const line of rl) {
    if (!line.trim()) continue;
    try {
      out.push(JSON.parse(line));
    } catch {
      /* partial last line while a session is running */
    }
  }
  return out;
}

export type DaySessions = Record<string, Array<{ at: number; md: string }>>;

/** Every Claude Code session under `root` that was touched in [from, to], rendered per day. Null when the folder is missing. */
export async function collectClaudeSessions(root: string, from: Date, to: Date, home = process.env.HOME ?? ""): Promise<{ perDay: DaySessions; sessions: number } | null> {
  let projects: string[];
  try {
    projects = await readdir(root);
  } catch {
    return null;
  }
  const perDay: DaySessions = {};
  let sessions = 0;
  for (const p of projects) {
    const dir = join(root, p);
    let files: string[];
    try {
      files = (await readdir(dir)).filter((f) => f.endsWith(".jsonl"));
    } catch {
      continue;
    }
    for (const f of files) {
      const full = join(dir, f);
      if ((await stat(full)).mtime < from) continue; // untouched since the window started
      const days = summarize(await readJsonl(full), from, to);
      for (const [day, s] of days) {
        if (!s.sessionId) s.sessionId = basename(f, ".jsonl");
        (perDay[day] ??= []).push({ at: s.first.getTime(), md: renderSession(s, home) });
        sessions++;
      }
    }
  }
  return { perDay, sessions };
}

export const claudeCodeSource: Source = {
  name: "claude-code",
  title: "Claude Code 세션",
  description: "~/.claude/projects 의 세션 기록에서 요청, 수정한 파일, 실행한 명령을 세션별로 요약합니다.",
  options: [{ key: "projectsDir", label: "세션 기록 폴더", kind: "path" }],
  async collect({ from, to, settings }) {
    const root = expandHome(String(settings.projectsDir ?? "~/.claude/projects"));
    const r = await collectClaudeSessions(root, from, to);
    if (!r) throw new Error(`세션 기록 폴더가 없습니다: ${root}`);
    const days: Record<string, string> = {};
    for (const [day, list] of Object.entries(r.perDay)) days[day] = list.sort((a, b) => a.at - b.at).map((x) => x.md).join("\n\n");
    return { days, note: `세션 ${r.sessions}개` };
  },
};
