import { execFile } from "node:child_process";
import { readdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { basename, join } from "node:path";
import { promisify } from "node:util";
import { expandHome } from "../config.ts";
import { redact } from "../redact.ts";
import { addTo, dayKey, hhmm, type Source } from "./types.ts";

const run = promisify(execFile);

const SKIP_DIRS = new Set(["node_modules", ".venv", "venv", "build", "dist", ".dart_tool", "Pods", "__pycache__"]);

export async function findRepos(root: string, depth: number): Promise<string[]> {
  const out: string[] = [];
  async function walk(dir: string, d: number): Promise<void> {
    if (existsSync(join(dir, ".git"))) out.push(dir);
    if (d >= depth) return;
    let entries;
    try {
      entries = await readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (!e.isDirectory() || e.name.startsWith(".") || SKIP_DIRS.has(e.name)) continue;
      await walk(join(dir, e.name), d + 1);
    }
  }
  await walk(root, 0);
  return out.sort();
}

type Commit = { repo: string; hash: string; date: Date; subject: string; files: number; ins: number; del: number };

export function parseGitLog(repo: string, out: string): Commit[] {
  const commits: Commit[] = [];
  for (const chunk of out.split("\x1e").slice(1)) {
    const [head, ...rest] = chunk.split("\n");
    const [hash, iso, subject] = head.split("\x1f");
    if (!hash || !iso) continue;
    const stat = rest.join("\n");
    const num = (re: RegExp) => Number(re.exec(stat)?.[1] ?? 0);
    commits.push({
      repo,
      hash,
      date: new Date(iso),
      subject: subject ?? "",
      files: num(/(\d+) files? changed/),
      ins: num(/(\d+) insertions?/),
      del: num(/(\d+) deletions?/),
    });
  }
  return commits;
}

export const gitSource: Source = {
  name: "git",
  title: "git 커밋",
  description: "저장소 상위 폴더 아래 모든 git 저장소에서 내 커밋을 모읍니다.",
  options: [
    { key: "reposRoot", label: "저장소 상위 폴더", kind: "path" },
    { key: "authorEmail", label: "작성자 이메일 (쉼표로 여러 개)", kind: "text" },
    { key: "depth", label: "탐색 깊이", kind: "number" },
  ],
  async collect({ from, to, settings, log }) {
    const root = expandHome(String(settings.reposRoot ?? "~"));
    const authors = String(settings.authorEmail ?? "").split(",").map((s) => s.trim()).filter(Boolean);
    if (!authors.length) throw new Error("작성자 이메일이 설정되지 않았습니다.");
    const repos = await findRepos(root, Number(settings.depth ?? 3));
    const commits: Commit[] = [];
    for (const repo of repos) {
      const args = ["-C", repo, "log", "--all", "--no-merges", `--since=${from.toISOString()}`, `--until=${to.toISOString()}`, "--date=iso-strict", "--pretty=format:%x1e%H%x1f%ad%x1f%s", "--shortstat"];
      for (const a of authors) args.push(`--author=${a}`);
      try {
        const { stdout } = await run("git", args, { maxBuffer: 64 * 1024 * 1024 });
        commits.push(...parseGitLog(basename(repo), stdout));
      } catch (err) {
        log(`git: ${repo} 건너뜀 (${(err as Error).message.split("\n")[0]})`);
      }
    }
    // the same commit can be reachable from several refs; --all already dedups per repo
    const byDay: Record<string, Record<string, string[]>> = {};
    for (const c of commits.sort((a, b) => a.date.getTime() - b.date.getTime())) {
      const day = dayKey(c.date);
      const stat = c.files ? ` (${c.files} files, +${c.ins} −${c.del})` : "";
      addTo((byDay[day] ??= {}), c.repo, `- ${hhmm(c.date)} \`${c.hash.slice(0, 7)}\` ${redact(c.subject)}${stat}`);
    }
    const days: Record<string, string> = {};
    for (const [day, repos2] of Object.entries(byDay)) {
      days[day] = Object.entries(repos2)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([repo, lines]) => `## ${repo}\n\n${lines.join("\n")}`)
        .join("\n\n");
    }
    return { days, note: `커밋 ${commits.length}개 · 저장소 ${repos.length}개 탐색` };
  },
};
