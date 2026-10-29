// zsh history. EXTENDED_HISTORY lines are ": <epoch>:<duration>;<command>".
// Lines without that prefix are still collected; they land on the day of the run.

import { appendFile, readdir, readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { expandHome } from "../config.ts";
import { redact } from "../redact.ts";
import { addTo, clip, dayKey, hhmm, type Source } from "./types.ts";

const TRIVIAL = /^(ls|ll|la|l|cd|pwd|clear|exit|history|z|j|cls|q|:q|fg|bg|jobs|which|echo|cat|less|head|tail|man|code|open|vim?|nvim|nano)(\s|$)/;

/** zsh writes non-ASCII bytes "metafied": 0x83 followed by (byte ^ 0x20). */
export function unmetafy(buf: Buffer): string {
  const out = Buffer.alloc(buf.length);
  let j = 0;
  for (let i = 0; i < buf.length; i++) {
    if (buf[i] === 0x83 && i + 1 < buf.length) out[j++] = buf[++i] ^ 0x20;
    else out[j++] = buf[i];
  }
  return out.subarray(0, j).toString("utf8");
}

export type HistoryEntry = { at: Date | null; command: string };

/** The form stored between backticks, so a later run can tell a command is already kept. */
function commandKey(cmd: string): string {
  return redact(clip(cmd, 200)).replace(/`/g, "'");
}

/** Commands already written to a day other than [today]. Today's file is rebuilt whole, so it is not a source of "already kept". */
async function commandsAlreadyKept(worklogDir: string, today: string): Promise<Set<string>> {
  const dir = join(worklogDir, "sources", "shell-history");
  const seen = new Set<string>();
  let names: string[];
  try {
    names = await readdir(dir);
  } catch {
    return seen;
  }
  for (const name of names) {
    if (!name.endsWith(".md") || name === `${today}.md`) continue;
    const text = await readFile(join(dir, name), "utf8");
    for (const m of text.matchAll(/`([^`]*)`/g)) seen.add(m[1]);
  }
  return seen;
}

// ── turning timestamps on ──────────────────────────────────────────────────────

/** The line the app appends; the comment marks it as ours. */
export const EXTENDED_HISTORY_LINE = "setopt EXTENDED_HISTORY  # zaevis";

/** zsh reads ~/.zshrc, or $ZDOTDIR/.zshrc when that is set. */
export function zshrcPath(env: NodeJS.ProcessEnv = process.env): string {
  return join(env.ZDOTDIR || env.HOME || homedir(), ".zshrc");
}

/** True when an uncommented `setopt` (or `set -o`) already turns EXTENDED_HISTORY on. zsh ignores case and underscores in option names. */
export function hasExtendedHistory(text: string): boolean {
  for (const raw of text.split("\n")) {
    const line = raw.replace(/#.*$/, "").trim();
    const m = /^(?:setopt|set\s+-o)\s+(.+)$/i.exec(line);
    if (!m) continue;
    if (m[1].split(/\s+/).some((opt) => opt.replace(/_/g, "").toLowerCase() === "extendedhistory")) return true;
  }
  return false;
}

/**
 * Appends `setopt EXTENDED_HISTORY  # zaevis` to the user's zshrc (created when missing) so new
 * terminals record a time with every command. Leaves the file alone when the option is already on.
 */
export async function enableExtendedHistory(env: NodeJS.ProcessEnv = process.env): Promise<{ file: string; changed: boolean }> {
  const file = zshrcPath(env);
  let text = "";
  try {
    text = await readFile(file, "utf8");
  } catch {
    text = "";
  }
  if (hasExtendedHistory(text)) return { file, changed: false };
  const sep = text.length === 0 || text.endsWith("\n") ? "" : "\n";
  await appendFile(file, `${sep}${EXTENDED_HISTORY_LINE}\n`);
  return { file, changed: true };
}

export function parseZshHistory(text: string): { entries: HistoryEntry[]; extended: boolean } {
  const entries: HistoryEntry[] = [];
  let extended = false;
  let current: HistoryEntry | null = null;
  for (const line of text.split("\n")) {
    if (current && current.command.endsWith("\\")) {
      current.command = current.command.slice(0, -1) + "\n" + line; // continuation line
      continue;
    }
    const m = /^: (\d{9,11}):\d+;(.*)$/.exec(line);
    if (m) {
      extended = true;
      current = { at: new Date(Number(m[1]) * 1000), command: m[2] };
      entries.push(current);
    } else if (line.trim()) {
      current = { at: null, command: line };
      entries.push(current);
    } else {
      current = null;
    }
  }
  return { entries, extended };
}

export const shellHistorySource: Source = {
  name: "shell-history",
  title: "셸 명령 이력",
  description: "터미널에서 친 명령(zsh 히스토리)을 모읍니다. 어떤 저장소에서 무엇을 빌드·배포·실행했는지의 흔적이며, cd·ls 같은 잡음과 비밀번호·토큰은 거릅니다. 명령을 친 시각이 없는 줄도 모으며, 그날 수집에 묶습니다. 시각까지 남기려면 zsh에 `setopt EXTENDED_HISTORY`를 켭니다.",
  options: [{ key: "historyFile", label: "히스토리 파일", kind: "path", help: "기본 ~/.zsh_history. bash는 지원하지 않습니다." }],
  async collect({ from, to, settings, config }) {
    const file = expandHome(String(settings.historyFile ?? "~/.zsh_history"));
    let buf: Buffer;
    try {
      buf = await readFile(file);
    } catch {
      throw new Error(`히스토리 파일이 없습니다: ${file}`);
    }
    const { entries } = parseZshHistory(unmetafy(buf));
    const undatedDay = dayKey(to);
    const kept = await commandsAlreadyKept(config.worklogDir, undatedDay);
    const byDay: Record<string, string[]> = {};
    let n = 0;
    let prev = "";
    for (const e of entries) {
      if (e.at && (e.at < from || e.at > to)) continue;
      const cmd = e.command.trim();
      if (!cmd || TRIVIAL.test(cmd) || cmd === prev) continue;
      const key = commandKey(cmd);
      if (!e.at && kept.has(key)) continue;
      prev = cmd;
      if (e.at) addTo(byDay, dayKey(e.at), `- ${hhmm(e.at)} \`${key}\``);
      else addTo(byDay, undatedDay, `- \`${key}\``);
      n++;
    }
    const days: Record<string, string> = {};
    for (const [d, lines] of Object.entries(byDay)) days[d] = lines.join("\n");
    return { days, note: `명령 ${n}개` };
  },
};
