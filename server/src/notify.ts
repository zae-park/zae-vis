// OS notifications from the server side, so they work even when the app is closed (the nightly
// collect, a transcription that finished, a digest proposal waiting). Nothing is sent anywhere:
// macOS uses osascript, Windows a toast through PowerShell, Linux notify-send when present.
// Setting: config.json → notifications (default true).

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { loadConfig } from "./config.ts";

const esc = (s: string) => s.replace(/["\\]/g, " ").replace(/\s+/g, " ").trim().slice(0, 200);

export type Notifier = (title: string, body: string) => void;

/** Fire-and-forget; failures are swallowed (a notification is never worth breaking a job). */
export const notify: Notifier = (title, body) => {
  try {
    if (!loadConfig().notifications) return;
  } catch {
    return;
  }
  send(title, body);
};

export function send(title: string, body: string, platform = process.platform): void {
  const t = esc(title);
  const b = esc(body);
  let cmd: string;
  let args: string[];
  if (platform === "darwin") {
    cmd = "osascript";
    args = ["-e", `display notification "${b}" with title "zaevis" subtitle "${t}"`];
  } else if (platform === "win32") {
    cmd = "powershell";
    args = ["-NoProfile", "-Command", toastScript(t, b)];
  } else if (existsSync("/usr/bin/notify-send")) {
    cmd = "/usr/bin/notify-send";
    args = [`zaevis · ${t}`, b];
  } else return;
  try {
    spawn(cmd, args, { stdio: "ignore", detached: true, windowsHide: true }).on("error", () => {}).unref();
  } catch {}
}

/** Windows 10/11 toast via WinRT from PowerShell (no module to install). */
export function toastScript(title: string, body: string): string {
  const x = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/'/g, "&apos;");
  return [
    "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null",
    "[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null",
    `$xml = New-Object Windows.Data.Xml.Dom.XmlDocument`,
    `$xml.LoadXml('<toast><visual><binding template="ToastGeneric"><text>zaevis · ${x(title)}</text><text>${x(body)}</text></binding></visual></toast>')`,
    `[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('zaevis').Show((New-Object Windows.UI.Notifications.ToastNotification $xml))`,
  ].join("; ");
}
