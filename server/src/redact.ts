// Masks secrets before anything is written into the worklog (and therefore the search index),
// and before a prompt leaves the machine (question, report, OpenRouter digest).

import { copyFile, readdir, readFile, writeFile } from "node:fs/promises";
import { extname, join } from "node:path";

type Rule = [string, RegExp, string | ((m: string, ...g: string[]) => string)];

const RULES: Rule[] = [
  ["private-key", /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, "[PRIVATE KEY]"],
  ["bearer", /\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}/g, "$1 ***"],
  ["jwt", /\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g, "jwt***"],
  // OpenAI · Anthropic · OpenRouter (sk-or-v1-…) · DeepSeek …
  ["sk", /\b(sk-(?:ant-|proj-)?[A-Za-z0-9_-]{16,})/g, "sk-***"],
  ["stripe", /\b((?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,})/g, "stripe***"],
  ["github", /\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})/g, "gh_***"],
  ["gitlab", /\bglpat-[A-Za-z0-9_-]{20,}/g, "glpat-***"],
  ["npm", /\bnpm_[A-Za-z0-9]{30,}\b/g, "npm_***"],
  ["aws", /\bAKIA[0-9A-Z]{16}\b/g, "AKIA***"],
  ["slack", /\bxox[abprs]-[A-Za-z0-9-]{10,}/g, "xox-***"],
  ["slack-webhook", /(hooks\.slack\.com\/services\/)[A-Za-z0-9/_-]{20,}/g, "$1***"],
  ["discord-webhook", /(discord(?:app)?\.com\/api\/webhooks\/\d+\/)[A-Za-z0-9_-]{20,}/g, "$1***"],
  ["telegram", /\b(\d{8,10}):[A-Za-z0-9_-]{35}\b/g, "$1:***"],
  ["databricks", /\bdapi[0-9a-f]{32}\b/g, "dapi***"],
  ["google", /\bAIza[0-9A-Za-z_-]{35}\b/g, "AIza***"],
  ["google-oauth", /\bya29\.[A-Za-z0-9_-]{20,}/g, "ya29.***"],
  ["huggingface", /\bhf_[A-Za-z0-9]{20,}\b/g, "hf_***"],
  // mysql -pSECRET (password glued to -p)
  ["mysql-p", /(\bmysql(?:dump|admin)?\b[^\n]*?\s-p)([^\s'"]{3,})/g, "$1***"],
  // key=value / key: value / --key value for secret-looking names
  [
    "key-value",
    /\b([A-Za-z0-9_.-]*(?:password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|credential)[A-Za-z0-9_.-]*)(\s*[=:]\s*|\s+)(["']?)([^\s"']{4,})\3/gi,
    (m: string, key: string, sep: string, q: string, value: string) => (value.includes("***") ? m : `${key}${sep}${q}***${q}`),
  ],
  // user:password@host in URLs
  ["url-password", /(\/\/[^/\s:@]+):([^/\s@*]{3,})@/g, "$1:***@"],
];

export function redact(text: string): string {
  let out = text;
  for (const [, re, rep] of RULES) out = out.replace(re, rep as never);
  return out;
}

/** Which rules fire on `text` and how often (for `zaevis redact`). Never returns the secret itself. */
export function findSecrets(text: string): Record<string, number> {
  const hits: Record<string, number> = {};
  let cur = text;
  for (const [name, re, rep] of RULES) {
    let n = 0;
    const next = cur.replace(re, (...args) => {
      const m = args[0] as string;
      const r = typeof rep === "string" ? m.replace(new RegExp(re.source, re.flags.replace("g", "")), rep) : (rep as (...a: unknown[]) => string)(...args);
      if (r !== m) n++;
      return r;
    });
    if (n) hits[name] = n;
    cur = next;
  }
  return hits;
}

/** Copies a text file, masking secrets on the way (transcripts dropped in from outside). */
export async function copyRedacted(src: string, dest: string): Promise<void> {
  if (!TEXT_FILE.has(extname(src).toLowerCase())) return copyFile(src, dest);
  await writeFile(dest, redact(await readFile(src, "utf8")));
}

const TEXT_FILE = new Set([".md", ".txt", ".json", ".jsonl", ".srt", ".vtt", ".csv", ".log"]);
/** Folders the scan skips: binaries, and zaevis' own state the index never reads. */
const SKIP_DIR = new Set([".git", "node_modules", "audio", ".autorag", ".obsidian"]);

export interface ScanHit {
  /** worklog-relative, `/`-separated */
  file: string;
  rules: Record<string, number>;
}

/**
 * Walks the worklog for secrets that were stored before a rule existed (or came in through a path
 * that did not mask). With `apply`, rewrites those files masked. The index catches up on the next refresh.
 */
export async function scanWorklog(root: string, opts: { apply?: boolean } = {}): Promise<ScanHit[]> {
  const hits: ScanHit[] = [];
  const walk = async (dir: string, rel: string): Promise<void> => {
    let entries;
    try {
      entries = await readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      const abs = join(dir, e.name);
      const r = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory()) {
        if (!SKIP_DIR.has(e.name)) await walk(abs, r);
        continue;
      }
      if (!e.isFile() || !TEXT_FILE.has(extname(e.name).toLowerCase())) continue;
      const text = await readFile(abs, "utf8").catch(() => null);
      if (text === null) continue;
      const rules = findSecrets(text);
      if (!Object.keys(rules).length) continue;
      hits.push({ file: r, rules });
      if (opts.apply) await writeFile(abs, redact(text));
    }
  };
  await walk(root, "");
  return hits;
}
