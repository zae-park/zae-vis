// Daily collect + index via macOS launchd (a LaunchAgent in ~/Library/LaunchAgents).
// launchd runs a missed StartCalendarInterval job when the Mac wakes; RunAtLoad + `--if-stale`
// covers the case where the Mac was off at the scheduled time.

import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { stateDir } from "./config.ts";

const run = promisify(execFile);
export const LABEL = "io.github.zaepark.zaevis.daily";
export const plistPath = (): string => join(homedir(), "Library", "LaunchAgents", `${LABEL}.plist`);
export const zaevisBin = (): string => resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "bin", "zaevis");

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

export function parseTime(hhmm: string): { hour: number; minute: number } {
  const m = /^(\d{1,2}):(\d{2})$/.exec(hhmm.trim());
  if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) throw new Error(`시각 형식이 올바르지 않습니다: ${hhmm} (예: 18:30)`);
  return { hour: Number(m[1]), minute: Number(m[2]) };
}

export function renderPlist(opts: { dailyAt: string; bin: string; path: string; logFile: string }): string {
  const { hour, minute } = parseTime(opts.dailyAt);
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${LABEL}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${esc(opts.bin)}</string>
		<string>daily</string>
		<string>--if-stale</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>${esc(opts.path)}</string>
	</dict>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Hour</key>
		<integer>${hour}</integer>
		<key>Minute</key>
		<integer>${minute}</integer>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>StandardOutPath</key>
	<string>${esc(opts.logFile)}</string>
	<key>StandardErrorPath</key>
	<string>${esc(opts.logFile)}</string>
</dict>
</plist>
`;
}

function launchdPath(): string {
  const h = homedir();
  const dirs = [dirname(process.execPath), "/opt/homebrew/bin", "/usr/local/bin", join(h, ".cargo", "bin"), join(h, ".local", "bin"), "/usr/bin", "/bin", "/usr/sbin", "/sbin"];
  return [...new Set(dirs)].join(":");
}

const domain = () => `gui/${process.getuid?.() ?? 501}`;

export type ScheduleStatus = { supported: boolean; installed: boolean; loaded: boolean; dailyAt: string | null; plist: string; hint?: string };

export async function scheduleStatus(): Promise<ScheduleStatus> {
  const plist = plistPath();
  const base = { plist, supported: process.platform === "darwin" };
  if (!existsSync(plist)) {
    return { ...base, installed: false, loaded: false, dailyAt: null, hint: base.supported ? undefined : cronHint("18:30") };
  }
  const xml = await readFile(plist, "utf8");
  const h = /<key>Hour<\/key>\s*<integer>(\d+)<\/integer>/.exec(xml)?.[1];
  const m = /<key>Minute<\/key>\s*<integer>(\d+)<\/integer>/.exec(xml)?.[1];
  const dailyAt = h && m ? `${h.padStart(2, "0")}:${m.padStart(2, "0")}` : null;
  let loaded = false;
  if (base.supported) loaded = await run("launchctl", ["print", `${domain()}/${LABEL}`]).then(() => true, () => false);
  return { ...base, installed: true, loaded, dailyAt };
}

export function cronHint(dailyAt: string): string {
  const { hour, minute } = parseTime(dailyAt);
  return `crontab -e 에 추가: ${minute} ${hour} * * * ${zaevisBin()} daily --if-stale`;
}

export async function installSchedule(dailyAt: string): Promise<ScheduleStatus> {
  parseTime(dailyAt);
  if (process.platform !== "darwin") return { supported: false, installed: false, loaded: false, dailyAt, plist: plistPath(), hint: cronHint(dailyAt) };
  await mkdir(dirname(plistPath()), { recursive: true });
  await mkdir(stateDir(), { recursive: true });
  await writeFile(plistPath(), renderPlist({ dailyAt, bin: zaevisBin(), path: launchdPath(), logFile: join(stateDir(), "daily.log") }));
  await run("launchctl", ["bootout", `${domain()}/${LABEL}`]).catch(() => {});
  await run("launchctl", ["bootstrap", domain(), plistPath()]);
  return scheduleStatus();
}

export async function removeSchedule(): Promise<ScheduleStatus> {
  if (process.platform === "darwin") await run("launchctl", ["bootout", `${domain()}/${LABEL}`]).catch(() => {});
  await rm(plistPath(), { force: true });
  return scheduleStatus();
}

/** Run if today's slot has passed and hasn't run yet, or if the last run is more than 36h old. */
export function isStale(lastDaily: Date | null, dailyAt: string, now = new Date()): boolean {
  if (!lastDaily) return true;
  const { hour, minute } = parseTime(dailyAt);
  const slot = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, minute);
  if (now >= slot && lastDaily < slot) return true;
  return now.getTime() - lastDaily.getTime() > 36 * 3_600_000;
}
