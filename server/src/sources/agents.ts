// "에이전트 세션": one data source for every coding/chat agent that keeps a local record —
// Claude Code (~/.claude/projects), Codex CLI (~/.codex/sessions), Gemini CLI (~/.gemini/tmp/*/chats)
// and a ChatGPT data export (conversations.json in a folder the user points at). Each provider is a
// toggle; the day file groups sessions under "## <provider> · HH:MM–HH:MM title".
//
// Formats other than Claude Code's are read defensively: a line or node we do not understand is
// skipped, never fatal. Each provider's summary says how many sessions it found.

import { readdir, readFile, stat } from "node:fs/promises";
import { basename, join } from "node:path";
import { expandHome } from "../config.ts";
import { redact } from "../redact.ts";
import { collectClaudeSessions, readJsonl, renderSession, setReply, type SessionDay } from "./claudeCode.ts";
import { clip, dayKey, type Source } from "./types.ts";

type Entry = Record<string, any>;
type PerDay = Record<string, Array<{ at: number; md: string }>>;

const PROVIDERS = {
  claude: { label: "Claude Code", option: { key: "claude", label: "Claude Code", kind: "bool" as const, help: "~/.claude/projects 의 세션 — 요청, 고친 파일, 실행한 명령" } },
  codex: { label: "Codex CLI", option: { key: "codex", label: "Codex CLI", kind: "bool" as const, help: "~/.codex/sessions 의 세션 기록 (OpenAI Codex 터미널 에이전트)" } },
  gemini: { label: "Gemini CLI", option: { key: "gemini", label: "Gemini CLI", kind: "bool" as const, help: "~/.gemini/tmp 의 대화 기록" } },
};

/** "## 11:52–12:30 title" → "## Claude Code · 11:52–12:30 title", so one day file can hold every provider. */
function tagProvider(md: string, label: string): string {
  return md.replace(/^## /, `## ${label} · `);
}

function newSession(id: string, at: Date, cwd = ""): SessionDay {
  return { sessionId: id, title: "", cwd, branch: "", first: at, last: at, prompts: [], replies: [], files: new Set(), commands: [], lastAnswer: "" };
}

function touch(s: SessionDay, t: Date): void {
  if (t < s.first) s.first = t;
  if (t > s.last) s.last = t;
}

function textOf(content: unknown): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((b) => (typeof b === "string" ? b : typeof b?.text === "string" ? b.text : typeof b?.content === "string" ? b.content : ""))
      .filter(Boolean)
      .join("\n");
  }
  return "";
}

async function walk(dir: string, keep: (name: string) => boolean, depth = 4): Promise<string[]> {
  if (depth < 0) return [];
  let names: Array<{ name: string; isDirectory(): boolean; isFile(): boolean }>;
  try {
    names = await readdir(dir, { withFileTypes: true });
  } catch {
    return [];
  }
  const out: string[] = [];
  for (const e of names) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...(await walk(p, keep, depth - 1)));
    else if (e.isFile() && keep(e.name)) out.push(p);
  }
  return out;
}

// ── Codex CLI: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl ────────────────────

/** One Codex rollout file → sessions per day (the user's messages, the last reply, shell commands). */
export function summarizeCodex(lines: Entry[], from: Date, to: Date, fallbackId: string): Map<string, SessionDay> {
  const days = new Map<string, SessionDay>();
  let cwd = "";
  let id = fallbackId;
  for (const line of lines) {
    const p = (line.payload ?? line) as Entry;
    if (p.type === "session_meta" || line.type === "session_meta") {
      cwd = String(p.cwd ?? p.payload?.cwd ?? cwd);
      id = String(p.id ?? id);
      continue;
    }
    const ts = line.timestamp ?? p.timestamp;
    if (!ts) continue;
    const t = new Date(ts);
    if (Number.isNaN(t.getTime()) || t < from || t > to) continue;
    const role = p.role ?? p.message?.role;
    const kind = p.type;
    const day = dayKey(t);
    let s = days.get(day);
    const ensure = () => {
      if (!s) {
        s = newSession(id, t, cwd);
        days.set(day, s);
      }
      touch(s, t);
      return s;
    };
    if (role === "user") {
      const text = textOf(p.content ?? p.message?.content).replace(/<environment_context>[\s\S]*?<\/environment_context>/g, "").trim();
      if (text && !/^<(user_instructions|environment)/.test(text)) {
        const s = ensure();
        s.prompts.push(text);
        s.replies.push("");
      }
    } else if (role === "assistant") {
      const text = textOf(p.content ?? p.message?.content).trim();
      if (text) setReply(ensure(), text);
    } else if (kind === "function_call" || kind === "tool_call" || kind === "local_shell_call") {
      let cmd = "";
      try {
        const a = typeof p.arguments === "string" ? JSON.parse(p.arguments) : (p.arguments ?? p.action ?? {});
        const c = a.command ?? a.cmd;
        cmd = Array.isArray(c) ? c.join(" ") : String(c ?? "");
      } catch {}
      if (cmd) ensure().commands.push(cmd);
    } else if (kind === "file_change" || kind === "patch") {
      for (const f of (p.changes ?? p.files ?? []) as Entry[]) {
        const path = typeof f === "string" ? f : f.path;
        if (path) ensure().files.add(String(path));
      }
    }
  }
  for (const s of days.values()) if (!s.title && s.prompts[0]) s.title = clip(s.prompts[0], 60);
  return days;
}

async function collectCodex(root: string, from: Date, to: Date, home: string): Promise<{ perDay: PerDay; sessions: number } | null> {
  try {
    await stat(root);
  } catch {
    return null;
  }
  const perDay: PerDay = {};
  let sessions = 0;
  for (const file of await walk(root, (n) => n.endsWith(".jsonl"))) {
    if ((await stat(file)).mtime < from) continue;
    const days = summarizeCodex(await readJsonl(file), from, to, basename(file, ".jsonl").replace(/^rollout-/, ""));
    for (const [day, s] of days) {
      (perDay[day] ??= []).push({ at: s.first.getTime(), md: tagProvider(renderSession(s, home), PROVIDERS.codex.label) });
      sessions++;
    }
  }
  return { perDay, sessions };
}

// ── Gemini CLI: ~/.gemini/tmp/<project>/chats/*.json ────────────────────────────

/** A saved Gemini CLI chat (JSON with `messages`) → sessions per day. */
export function summarizeGemini(doc: Entry, from: Date, to: Date, fallbackId: string): Map<string, SessionDay> {
  const days = new Map<string, SessionDay>();
  const messages = (Array.isArray(doc.messages) ? doc.messages : Array.isArray(doc.history) ? doc.history : []) as Entry[];
  const id = String(doc.sessionId ?? doc.id ?? fallbackId);
  const base = doc.startTime ?? doc.lastUpdated;
  for (const m of messages) {
    const t = new Date(m.timestamp ?? m.time ?? base ?? NaN);
    if (Number.isNaN(t.getTime()) || t < from || t > to) continue;
    const day = dayKey(t);
    let s = days.get(day);
    if (!s) {
      s = newSession(id, t, String(doc.cwd ?? doc.projectRoot ?? ""));
      days.set(day, s);
    }
    touch(s, t);
    const role = String(m.type ?? m.role ?? "");
    const text = textOf(m.content ?? m.parts ?? m.text).trim();
    if (!text) continue;
    if (role === "user") {
      s.prompts.push(text);
      s.replies.push("");
    } else if (/^(gemini|model|assistant)$/.test(role)) setReply(s, text);
  }
  for (const s of days.values()) if (!s.title && s.prompts[0]) s.title = clip(s.prompts[0], 60);
  return days;
}

async function collectGemini(root: string, from: Date, to: Date, home: string): Promise<{ perDay: PerDay; sessions: number } | null> {
  try {
    await stat(root);
  } catch {
    return null;
  }
  const perDay: PerDay = {};
  let sessions = 0;
  for (const file of await walk(root, (n) => n.endsWith(".json") && /chat|session/i.test(n))) {
    if ((await stat(file)).mtime < from) continue;
    let doc: Entry;
    try {
      doc = JSON.parse(await readFile(file, "utf8"));
    } catch {
      continue;
    }
    const days = summarizeGemini(doc, from, to, basename(file, ".json"));
    for (const [day, s] of days) {
      (perDay[day] ??= []).push({ at: s.first.getTime(), md: tagProvider(renderSession(s, home), PROVIDERS.gemini.label) });
      sessions++;
    }
  }
  return { perDay, sessions };
}

// ── ChatGPT: a data export folder with conversations.json ──────────────────────

/** conversations.json (ChatGPT "export data") → sessions per day, one per conversation. */
export function summarizeChatgpt(conversations: Entry[], from: Date, to: Date): Map<string, SessionDay[]> {
  const out = new Map<string, SessionDay[]>();
  for (const c of conversations) {
    const mapping = (c.mapping ?? {}) as Record<string, Entry>;
    const msgs = Object.values(mapping)
      .map((n) => n?.message)
      .filter((m): m is Entry => !!m && typeof m.create_time === "number")
      .sort((a, b) => a.create_time - b.create_time);
    const byDay = new Map<string, SessionDay>();
    for (const m of msgs) {
      const t = new Date(m.create_time * 1000);
      if (t < from || t > to) continue;
      const role = m.author?.role;
      const text = textOf(m.content?.parts).trim();
      if (!text || (role !== "user" && role !== "assistant")) continue;
      const day = dayKey(t);
      let s = byDay.get(day);
      if (!s) {
        s = newSession(String(c.id ?? c.conversation_id ?? ""), t);
        s.title = String(c.title ?? "");
        byDay.set(day, s);
      }
      touch(s, t);
      if (role === "user") {
        s.prompts.push(text);
        s.replies.push("");
      } else setReply(s, text);
    }
    for (const [day, s] of byDay) out.set(day, [...(out.get(day) ?? []), s]);
  }
  return out;
}

async function collectChatgpt(dir: string, from: Date, to: Date): Promise<{ perDay: PerDay; sessions: number } | null> {
  const file = join(dir, "conversations.json");
  let conversations: Entry[];
  try {
    conversations = JSON.parse(await readFile(file, "utf8"));
  } catch {
    return null;
  }
  const perDay: PerDay = {};
  let sessions = 0;
  for (const [day, list] of summarizeChatgpt(Array.isArray(conversations) ? conversations : [], from, to)) {
    for (const s of list) {
      (perDay[day] ??= []).push({ at: s.first.getTime(), md: tagProvider(renderSession(s), "ChatGPT") });
      sessions++;
    }
  }
  return { perDay, sessions };
}

// ── the source ────────────────────────────────────────────────────────────────

export const agentsSource: Source = {
  name: "agent-sessions",
  title: "에이전트 세션",
  description: "Claude Code · Codex CLI · Gemini CLI 의 로컬 세션 기록과 ChatGPT 데이터 내보내기에서 요청, 수정한 파일, 실행한 명령을 세션별로 요약합니다. 각 도구는 켜고 끌 수 있고, 기록이 없는 도구는 건너뜁니다.",
  options: [
    PROVIDERS.claude.option,
    PROVIDERS.codex.option,
    PROVIDERS.gemini.option,
    { key: "chatgptExportDir", label: "ChatGPT 내보내기 폴더 (선택)", kind: "path", help: "ChatGPT 설정 → 데이터 제어 → 데이터 내보내기로 받은 zip을 푼 폴더 (conversations.json이 있는 곳). 비우면 건너뜁니다." },
  ],
  async collect({ from, to, settings, log }) {
    const home = process.env.HOME ?? process.env.USERPROFILE ?? "";
    const on = (k: string) => settings[k] !== false;
    const perDay: PerDay = {};
    const notes: string[] = [];
    const merge = (label: string, r: { perDay: PerDay; sessions: number } | null) => {
      if (r === null) {
        notes.push(`${label} 기록 없음`);
        return;
      }
      for (const [day, list] of Object.entries(r.perDay)) (perDay[day] ??= []).push(...list);
      notes.push(`${label} ${r.sessions}개`);
    };
    if (on("claude")) {
      const r = await collectClaudeSessions(expandHome(String(settings.claudeDir ?? "~/.claude/projects")), from, to, home);
      merge(PROVIDERS.claude.label, r && { sessions: r.sessions, perDay: Object.fromEntries(Object.entries(r.perDay).map(([d, l]) => [d, l.map((x) => ({ ...x, md: tagProvider(x.md, PROVIDERS.claude.label) }))])) });
    }
    if (on("codex")) merge(PROVIDERS.codex.label, await collectCodex(expandHome(String(settings.codexDir ?? "~/.codex/sessions")), from, to, home));
    if (on("gemini")) merge(PROVIDERS.gemini.label, await collectGemini(expandHome(String(settings.geminiDir ?? "~/.gemini/tmp")), from, to, home));
    const chatgpt = String(settings.chatgptExportDir ?? "").trim();
    if (chatgpt) {
      const r = await collectChatgpt(expandHome(chatgpt), from, to);
      if (r === null) log(`ChatGPT: ${chatgpt}/conversations.json 을 읽지 못했습니다`);
      merge("ChatGPT", r);
    }
    const days: Record<string, string> = {};
    for (const [day, list] of Object.entries(perDay)) days[day] = list.sort((a, b) => a.at - b.at).map((x) => redact(x.md)).join("\n\n");
    return { days, note: notes.join(" · ") || "켜진 도구 없음" };
  },
};
