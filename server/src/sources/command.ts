// User-defined connector: any shell command that prints Markdown.
//
//   ~/.zaevis/sources.json
//   { "custom": [ { "name": "slack", "command": "python3 ~/bin/slack_export.py --since {from} --until {to}" } ] }
//
// {from} / {to} are replaced with ISO timestamps, {fromDate} / {toDate} with YYYY-MM-DD (for tools
// like `find -newermt` that do not parse the long form). Output goes to today's file, or split by
// lines of the form "<!-- zaevis:date 2026-10-21 -->" to place sections on specific days.

import { exec } from "node:child_process";
import { redact } from "../redact.ts";
import { dayKey, type Source } from "./types.ts";

const MARK = /^<!--\s*zaevis:date\s+(\d{4}-\d{2}-\d{2})\s*-->\s*$/;

export function splitByDate(output: string, today: string): Record<string, string> {
  const days: Record<string, string[]> = {};
  let current = today;
  for (const line of output.split("\n")) {
    const m = MARK.exec(line);
    if (m) {
      current = m[1];
      continue;
    }
    (days[current] ??= []).push(line);
  }
  const out: Record<string, string> = {};
  for (const [d, lines] of Object.entries(days)) {
    const text = lines.join("\n").trim();
    if (text) out[d] = text;
  }
  return out;
}

export const SAFE_NAME = /^[a-z0-9][a-z0-9_-]{0,39}$/;

export function commandSource(name: string, command: string, description?: string): Source {
  return {
    name,
    title: name,
    description: description ?? `사용자 커넥터: ${command}`,
    options: [{ key: "command", label: "실행할 명령", kind: "text" }],
    async collect({ from, to }) {
      const cmd = command
        .replaceAll("{fromDate}", dayKey(from))
        .replaceAll("{toDate}", dayKey(to))
        .replaceAll("{from}", from.toISOString())
        .replaceAll("{to}", to.toISOString());
      const stdout = await new Promise<string>((resolve, reject) => {
        exec(cmd, { shell: process.platform === "win32" ? process.env.ComSpec || "cmd.exe" : process.env.SHELL || "/bin/sh", maxBuffer: 32 * 1024 * 1024, timeout: 10 * 60_000 }, (err, so, se) =>
          err ? reject(new Error(`명령 실패: ${String(se || err.message).trim().split("\n").slice(-2).join(" ")}`)) : resolve(so),
        );
      });
      const days = splitByDate(redact(stdout), dayKey(to));
      return { days, note: `${Object.keys(days).length}일치` };
    },
  };
}
