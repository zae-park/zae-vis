// Runs an external program. On Windows a `.cmd` shim needs a shell, and a shell script
// (the kind tests and some installers drop on PATH) only runs through Git bash.
import { execFile, spawn, type ExecFileException, type ExecFileOptions, type SpawnOptions } from "node:child_process";

type Run = { command: string; args: string[]; shell?: boolean };

export function commandFor(bin: string, args: string[]): Run {
  if (process.platform === "win32") {
    if (/\.(cmd|bat)$/i.test(bin)) return { command: bin, args, shell: true };
    if (!/\.(exe|com)$/i.test(bin)) return { command: "bash", args: [bin, ...args] };
  }
  return { command: bin, args };
}

export function spawnBin(bin: string, args: string[], opts: SpawnOptions = {}) {
  const run = commandFor(bin, args);
  return spawn(run.command, run.args, { ...opts, shell: run.shell ?? opts.shell, windowsHide: opts.windowsHide ?? process.platform === "win32" });
}

export function execFileBin(
  bin: string,
  args: string[],
  opts: ExecFileOptions,
  callback: (err: ExecFileException | null, stdout: string | Buffer, stderr: string | Buffer) => void,
) {
  const run = commandFor(bin, args);
  return execFile(run.command, run.args, { ...opts, shell: run.shell }, callback);
}
