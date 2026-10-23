// Masks secrets before anything is written into the worklog (and therefore the search index).

const RULES: Array<[RegExp, string | ((m: string, ...g: string[]) => string)]> = [
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, "[PRIVATE KEY]"],
  [/\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}/g, "$1 ***"],
  [/\b(sk-(?:ant-|proj-)?[A-Za-z0-9_-]{16,})/g, "sk-***"],
  [/\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})/g, "gh_***"],
  [/\bAKIA[0-9A-Z]{16}\b/g, "AKIA***"],
  [/\bxox[abprs]-[A-Za-z0-9-]{10,}/g, "xox-***"],
  [/\bdapi[0-9a-f]{32}\b/g, "dapi***"],
  [/\bAIza[0-9A-Za-z_-]{35}\b/g, "AIza***"],
  [/\bhf_[A-Za-z0-9]{20,}\b/g, "hf_***"],
  // key=value / key: value / --key value for secret-looking names
  [
    /\b([A-Za-z0-9_.-]*(?:password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|credential)[A-Za-z0-9_.-]*)(\s*[=:]\s*|\s+)(["']?)([^\s"']{4,})\3/gi,
    (_m, key: string, sep: string, q: string) => `${key}${sep}${q}***${q}`,
  ],
  // user:password@host in URLs
  [/(\/\/[^/\s:@]+):([^/\s@]{3,})@/g, "$1:***@"],
];

export function redact(text: string): string {
  let out = text;
  for (const [re, rep] of RULES) out = out.replace(re, rep as never);
  return out;
}
