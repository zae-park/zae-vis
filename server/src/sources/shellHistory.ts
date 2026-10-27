// zsh history. Needs EXTENDED_HISTORY (": <epoch>:<duration>;<command>") for timestamps.

import { readFile } from "node:fs/promises";
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

export type HistoryEntry = { at: Date; command: string };

export function parseZshHistory(text: string): { entries: HistoryEntry[]; extended: boolean } {
  const entries: HistoryEntry[] = [];
  let extended = false;
  let current: HistoryEntry | null = null;
  for (const line of text.split("\n")) {
    const m = /^: (\d{9,11}):\d+;(.*)$/.exec(line);
    if (m) {
      extended = true;
      current = { at: new Date(Number(m[1]) * 1000), command: m[2] };
      entries.push(current);
    } else if (current && current.command.endsWith("\\")) {
      current.command = current.command.slice(0, -1) + "\n" + line; // continuation line
    }
  }
  return { entries, extended };
}

export const shellHistorySource: Source = {
  name: "shell-history",
  title: "셸 명령 이력",
  description: "터미널에서 친 명령(zsh 히스토리)을 시간순으로 모읍니다. 어떤 저장소에서 무엇을 빌드·배포·실행했는지의 흔적이며, cd·ls 같은 잡음과 비밀번호·토큰은 거릅니다. 시각이 남으려면 zsh에 `setopt EXTENDED_HISTORY`가 켜져 있어야 합니다.",
  options: [{ key: "historyFile", label: "히스토리 파일", kind: "path", help: "기본 ~/.zsh_history. bash는 지원하지 않습니다." }],
  async collect({ from, to, settings }) {
    const file = expandHome(String(settings.historyFile ?? "~/.zsh_history"));
    let buf: Buffer;
    try {
      buf = await readFile(file);
    } catch {
      throw new Error(`히스토리 파일이 없습니다: ${file}`);
    }
    const { entries, extended } = parseZshHistory(unmetafy(buf));
    if (!extended) {
      throw new Error("히스토리에 시각이 없습니다. ~/.zshrc 에 'setopt EXTENDED_HISTORY' 를 추가하면 그 뒤부터 수집됩니다.");
    }
    const byDay: Record<string, string[]> = {};
    let n = 0;
    let prev = "";
    for (const e of entries) {
      if (e.at < from || e.at > to) continue;
      const cmd = e.command.trim();
      if (!cmd || TRIVIAL.test(cmd) || cmd === prev) continue;
      prev = cmd;
      addTo(byDay, dayKey(e.at), `- ${hhmm(e.at)} \`${redact(clip(cmd, 200)).replace(/`/g, "'")}\``);
      n++;
    }
    const days: Record<string, string> = {};
    for (const [d, lines] of Object.entries(byDay)) days[d] = lines.join("\n");
    return { days, note: `명령 ${n}개` };
  },
};
