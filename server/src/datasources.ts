// External datasources of AutoRAG (Slack, Notion, Obsidian, GitHub, mail, RSS …) managed from zaevis.
//
// AutoRAG reads them from the `datasources` section of its config.json; one entry per connection,
// keyed by the template name (or an alias with `type`). This module knows the templates zaevis
// offers (title, what to install, which fields the connector needs), probes what is feasible on this
// machine (CLI on PATH, local archive present, token env set), and reads/writes that section while
// leaving the rest of the file alone. Only env-var *names* are ever stored — never a token value.
//
// Indexing and search stay inside AutoRAG: `autorag.refresh` with the `datasources` phase syncs every
// connection, and `autorag.search` mixes their hits in with the worklog ones (see context.ts).

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { expandHome } from "./config.ts";

export type FieldKind = "text" | "path" | "list" | "env";

export type DatasourceField = {
  key: string;
  label: string;
  kind: FieldKind;
  required?: boolean;
  help?: string;
  placeholder?: string;
  /** Default for `env` fields (the AutoRAG default, shown when the user leaves it empty). */
  defaultValue?: string;
};

export type DatasourceTemplate = {
  /** AutoRAG template name = config key. */
  name: string;
  title: string;
  description: string;
  /** External CLI the template needs; absent for connectors AutoRAG runs itself (obsidian, rss, github …). */
  cli?: { bin: string; install: string; homepage?: string };
  /** Default local archive the CLI keeps; exists → the user has already crawled something. */
  archive?: string;
  /** Only on this platform (spotlight = macOS). */
  platform?: NodeJS.Platform;
  /** Connector fields the UI asks for. Keys map 1:1 onto `connector` in config.json. */
  fields: DatasourceField[];
  /** Short note on what leaves the machine, for the card. */
  external?: string;
};

const home = homedir();
const h = (...p: string[]) => join(home, ...p);

const chatDb = (dir: string, file: string): DatasourceField => ({
  key: "databasePath",
  label: "아카이브 파일",
  kind: "path",
  placeholder: h(dir, file),
  help: "비우면 CLI 기본 위치를 씁니다.",
});

export const TEMPLATES: DatasourceTemplate[] = [
  {
    name: "obsidian",
    title: "Obsidian 볼트",
    description: "볼트의 Markdown 노트를 AutoRAG가 직접 색인합니다 (설치할 것 없음). 키워드·의미 검색 모두 됩니다.",
    fields: [{ key: "vaultPath", label: "볼트 폴더", kind: "path", required: true, placeholder: h("Documents", "Obsidian Vault") }],
    external: "없음 — 이 맥 안에서 색인합니다.",
  },
  {
    name: "slack",
    title: "Slack",
    description: "slacrawl이 모아 둔 워크스페이스·채널·스레드 아카이브를 검색합니다. 먼저 slacrawl로 로그인·수집해 두세요.",
    cli: { bin: "slacrawl", install: "npm install -g slacrawl", homepage: "https://github.com/openclaw/slacrawl" },
    archive: h(".slacrawl", "slacrawl.db"),
    fields: [
      { key: "workspace", label: "워크스페이스(팀) ID", kind: "text", required: true, placeholder: "T0435JHH63Z", help: "slacrawl이 여러 워크스페이스를 담고 있을 때 어느 것을 볼지. 없으면 빈 결과만 나옵니다." },
      chatDb(".slacrawl", "slacrawl.db"),
    ],
  },
  {
    name: "notion",
    title: "Notion",
    description: "notcrawl이 받아 둔 페이지·데이터베이스·블록 아카이브를 검색합니다 (키워드 검색).",
    cli: { bin: "notcrawl", install: "npm install -g notcrawl", homepage: "https://github.com/openclaw/notcrawl" },
    archive: h(".notcrawl", "notcrawl.db"),
    fields: [chatDb(".notcrawl", "notcrawl.db")],
  },
  {
    name: "discord",
    title: "Discord",
    description: "discrawl의 로컬 아카이브(데스크톱 앱 와이어탭, 봇 토큰 불필요)를 검색합니다.",
    cli: { bin: "discrawl", install: "npm install -g discrawl", homepage: "https://github.com/openclaw/discrawl" },
    archive: h(".discrawl", "discrawl.db"),
    fields: [chatDb(".discrawl", "discrawl.db")],
  },
  {
    name: "kakao",
    title: "카카오톡",
    description: "lazykatok이 맥 카카오톡에서 모은 대화 아카이브를 검색합니다.",
    cli: { bin: "lazykatok", install: "npm install -g lazykatok", homepage: "https://github.com/changeroa/lazykatok" },
    archive: h("Library", "Application Support", "katok", "archive.sqlite3"),
    platform: "darwin",
    fields: [{ key: "workspacePath", label: "데이터 폴더", kind: "path", placeholder: h("Library", "Application Support", "katok"), help: "비우면 lazykatok 기본 위치." }],
  },
  {
    name: "whatsapp",
    title: "WhatsApp",
    description: "wacrawl의 로컬 아카이브를 검색합니다.",
    cli: { bin: "wacrawl", install: "npm install -g wacrawl", homepage: "https://github.com/openclaw/wacrawl" },
    archive: h(".wacrawl", "wacrawl.db"),
    fields: [chatDb(".wacrawl", "wacrawl.db")],
  },
  {
    name: "telegram",
    title: "Telegram",
    description: "telecrawl의 로컬 데스크톱 아카이브를 검색합니다.",
    cli: { bin: "telecrawl", install: "npm install -g telecrawl", homepage: "https://github.com/openclaw/telecrawl" },
    archive: h(".telecrawl", "telecrawl.db"),
    fields: [chatDb(".telecrawl", "telecrawl.db")],
  },
  {
    name: "mailcrawl",
    title: "메일 (mailcrawl)",
    description: "mailcrawl이 Gmail·IMAP·Maildir에서 받아 둔 메일 아카이브를 검색합니다. 계정 로그인은 mailcrawl에서 합니다.",
    cli: { bin: "mailcrawl", install: "npm install -g mailcrawl", homepage: "https://github.com/NomaDamas/mailcrawl" },
    fields: [
      { key: "account", label: "계정 이름", kind: "text", placeholder: "work", help: "mailcrawl에 등록한 계정 id. 비우면 기본 계정." },
      { key: "mailbox", label: "메일함", kind: "text", placeholder: "INBOX" },
      { key: "dataDir", label: "데이터 폴더", kind: "path", help: "비우면 mailcrawl 기본 위치." },
    ],
  },
  {
    name: "mail-export",
    title: "메일 내보내기 (.mbox / .eml)",
    description: "메일 앱에서 내보낸 .mbox·.eml 파일이나 폴더를 AutoRAG가 직접 읽습니다 (설치할 것 없음, 키워드 검색).",
    fields: [{ key: "paths", label: "파일·폴더", kind: "list", required: true, placeholder: h("Mail", "export.mbox"), help: "한 줄에 하나씩." }],
    external: "없음",
  },
  {
    name: "github",
    title: "GitHub 이슈·PR",
    description: "GitHub REST API로 저장소의 이슈와 PR을 가져옵니다. 토큰은 환경 변수로만 넘깁니다 (값은 저장하지 않음).",
    fields: [
      { key: "repos", label: "저장소", kind: "list", required: true, placeholder: "owner/repo", help: "한 줄에 하나씩, owner/repo 꼴." },
      { key: "tokenEnv", label: "토큰 환경 변수 이름", kind: "env", defaultValue: "GITHUB_TOKEN", help: "서버를 띄운 셸에 이 변수가 있어야 합니다. 값이 아니라 이름만 저장됩니다." },
    ],
    external: "api.github.com에 저장소 목록·이슈·PR 요청을 보냅니다.",
  },
  {
    name: "github-gist",
    title: "GitHub Gist",
    description: "내 계정의 Gist를 가져와 색인합니다. 토큰 환경 변수가 없으면 `gh auth token`을 씁니다.",
    fields: [{ key: "tokenEnv", label: "토큰 환경 변수 이름", kind: "env", defaultValue: "GITHUB_TOKEN" }],
    external: "api.github.com에 Gist 목록·내용 요청을 보냅니다.",
  },
  {
    name: "cloud-drive",
    title: "클라우드 드라이브 (rclone)",
    description: "rclone 리모트(Google Drive, OneDrive, Dropbox …)의 문서를 받아 색인합니다. rclone config로 리모트를 먼저 만드세요.",
    cli: { bin: "rclone", install: "brew install rclone", homepage: "https://rclone.org" },
    fields: [
      { key: "remote", label: "rclone 리모트", kind: "text", required: true, placeholder: "gdrive:Documents", help: "`rclone listremotes`에 나오는 이름과 경로." },
      { key: "provider", label: "종류", kind: "text", placeholder: "drive", help: "drive · onedrive · dropbox … (선택)" },
    ],
    external: "rclone이 해당 클라우드에 접속합니다.",
  },
  {
    name: "rss",
    title: "RSS · 뉴스",
    description: "RSS 2.0·Atom 피드를 주기적으로 받아 색인합니다 (설치할 것 없음).",
    fields: [{ key: "feeds", label: "피드 주소", kind: "list", required: true, placeholder: "https://example.com/feed.xml", help: "한 줄에 하나씩." }],
    external: "피드 주소에 HTTP 요청을 보냅니다.",
  },
  {
    name: "spotlight",
    title: "macOS Spotlight",
    description: "mdfind로 Spotlight 질의에 맞는 파일을 찾아 본문을 색인합니다 (설치할 것 없음).",
    platform: "darwin",
    fields: [
      { key: "queries", label: "Spotlight 질의", kind: "list", required: true, placeholder: "kMDItemKind == 'PDF' && kMDItemTextContent == '*계약*'", help: "한 줄에 하나씩, mdfind 문법." },
      { key: "onlyIn", label: "이 폴더 안에서만", kind: "path", placeholder: h("Documents") },
    ],
    external: "없음",
  },
  {
    name: "clawgallery",
    title: "사진·스크린샷 (clawgallery)",
    description: "clawgallery가 OCR·시각 색인한 스크린샷·사진을 검색합니다.",
    cli: { bin: "clawgallery", install: "npm install -g clawgallery" },
    fields: [{ key: "path", label: "사진 폴더", kind: "path", placeholder: h("Pictures", "Screenshots") }],
  },
  {
    name: "hister",
    title: "브라우저 방문 기록 (Hister)",
    description: "별도로 설치해 켜 둔 Hister 서버(확장 프로그램이 방문한 페이지를 모음)를 검색합니다.",
    cli: { bin: "hister", install: "brew install hister && brew services start hister", homepage: "https://github.com/asciimoo/hister" },
    fields: [
      { key: "baseUrl", label: "Hister 주소", kind: "text", placeholder: "http://127.0.0.1:9876" },
      { key: "tokenEnv", label: "토큰 환경 변수 이름", kind: "env" },
    ],
  },
];

export const templateByName = (name: string): DatasourceTemplate | undefined => TEMPLATES.find((t) => t.name === name);

/** Korean label for a datasource id (template or alias) — used for search-hit labels too. */
export function datasourceLabel(id: string, type?: string): string {
  const t = templateByName(type ?? id);
  if (!t) return id;
  return type && type !== id ? `${t.title} (${id})` : t.title;
}

// ── probe ──────────────────────────────────────────────────────────────────────

const EXTRA_BIN_DIRS = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", h(".local", "bin"), h(".cargo", "bin"), h("go", "bin"), h(".bun", "bin"), h(".npm-global", "bin")];

/** Where a CLI is, searching PATH plus the usual install folders (the app's launchd env has a short PATH). */
export function findBin(bin: string, env: NodeJS.ProcessEnv = process.env): string | null {
  const dirs = [...(env.PATH ?? "").split(process.platform === "win32" ? ";" : ":"), ...EXTRA_BIN_DIRS].filter(Boolean);
  const names = process.platform === "win32" ? [`${bin}.exe`, `${bin}.cmd`, bin] : [bin];
  for (const d of dirs) for (const n of names) if (existsSync(join(d, n))) return join(d, n);
  return null;
}

export type Probe = {
  /** null when the template needs no CLI. */
  installed: boolean | null;
  binPath: string | null;
  /** The CLI's default archive exists (null: not applicable / unknown). */
  archive: boolean | null;
  /** Env var names the connection relies on and whether each is set in the server's environment. */
  env: Array<{ name: string; set: boolean }>;
  /** Why the template cannot be used here (wrong platform), else null. */
  unavailable: string | null;
};

export function probe(t: DatasourceTemplate, connector: Record<string, unknown> = {}, env: NodeJS.ProcessEnv = process.env): Probe {
  const unavailable = t.platform && t.platform !== process.platform ? `${t.platform === "darwin" ? "macOS" : t.platform}에서만 쓸 수 있습니다.` : null;
  const binPath = t.cli ? findBin(t.cli.bin, env) : null;
  const envs = t.fields
    .filter((f) => f.kind === "env")
    .map((f) => String(connector[f.key] ?? f.defaultValue ?? "").trim())
    .filter(Boolean)
    .map((name) => ({ name, set: typeof env[name] === "string" && env[name]!.length > 0 }));
  return {
    installed: t.cli ? binPath !== null : null,
    binPath,
    archive: t.archive ? existsSync(String(connector.databasePath || connector.workspacePath || t.archive)) : null,
    env: envs,
    unavailable,
  };
}

// ── config.json `datasources` section ─────────────────────────────────────────

export type DatasourceEntry = {
  enabled?: boolean;
  description?: string;
  type?: string;
  instanceId?: string;
  tags?: string[];
  connector?: Record<string, unknown>;
  channels?: { ids?: string[]; names?: string[] };
  [k: string]: unknown;
};

const SECRET_KEY = /token$|apikey$|api_key$|password|secret|credential/i;
const ENV_NAME = /^[A-Z_][A-Z0-9_]{0,63}$/;

function readConfig(file: string): Record<string, unknown> {
  if (!existsSync(file)) throw new Error(`AutoRAG가 설정되지 않았습니다 (${file} 없음). 'zaevis setup'을 먼저 실행하세요.`);
  const v = JSON.parse(readFileSync(file, "utf8")) as unknown;
  if (!v || typeof v !== "object" || Array.isArray(v)) throw new Error(`${file} 이(가) JSON 객체가 아닙니다.`);
  return v as Record<string, unknown>;
}

/** Atomic replace, like AutoRAG's own writer, so a crash never leaves a half-written config. */
function writeConfig(file: string, cfg: Record<string, unknown>): void {
  mkdirSync(dirname(file), { recursive: true });
  const tmp = join(dirname(file), `.${basename(file)}.${process.pid}.tmp`);
  writeFileSync(tmp, JSON.stringify(cfg, null, 2) + "\n");
  renameSync(tmp, file);
}

/** The configured connections: key → entry (`true` entries become `{}`; `false`/garbage are dropped). */
export function readDatasources(autoragConfig: string): Record<string, DatasourceEntry> {
  if (!existsSync(autoragConfig)) return {};
  const raw = readConfig(autoragConfig).datasources;
  const out: Record<string, DatasourceEntry> = {};
  if (!raw || typeof raw !== "object") return out;
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    if (v === true) out[k] = {};
    else if (v && typeof v === "object" && !Array.isArray(v)) out[k] = v as DatasourceEntry;
  }
  return out;
}

const strs = (v: unknown): string[] => (Array.isArray(v) ? v.map((x) => (typeof x === "string" ? x.trim() : "")).filter(Boolean) : typeof v === "string" ? v.split("\n").map((s) => s.trim()).filter(Boolean) : []);

/**
 * Validates and shapes a connector from the API into what AutoRAG expects for the template:
 * - fields declared by the template are typed (`list` → string[], `rss.feeds` → [{ url }], `path` → ~ expanded)
 * - `env` fields must look like an env-var name; keys that look like a credential are refused
 * - unknown keys are kept as-is (advanced options such as timeoutMs), minus anything secret-looking
 */
export function shapeConnector(t: DatasourceTemplate, input: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(input)) {
    if (SECRET_KEY.test(k) && !/Env$/.test(k)) throw new Error(`'${k}'는 저장할 수 없습니다. 토큰·비밀번호 값은 환경 변수에 두고 그 이름만 적으세요.`);
    const f = t.fields.find((x) => x.key === k);
    if (!f) {
      if (v !== null && v !== undefined && v !== "") out[k] = v;
      continue;
    }
    switch (f.kind) {
      case "list": {
        const list = strs(v);
        if (k === "feeds") out.feeds = list.map((url) => ({ url }));
        else if (list.length) out[k] = list;
        break;
      }
      case "env": {
        const name = String(v ?? "").trim();
        if (!name) break;
        if (!ENV_NAME.test(name)) throw new Error(`'${f.label}'은(는) 환경 변수 이름이어야 합니다 (예: GITHUB_TOKEN). 값을 넣지 마세요.`);
        out[k] = name;
        break;
      }
      case "path": {
        const p = String(v ?? "").trim();
        if (p) out[k] = expandHome(p);
        break;
      }
      default: {
        const s = String(v ?? "").trim();
        if (s) out[k] = s;
      }
    }
  }
  for (const f of t.fields) {
    if (!f.required) continue;
    const v = out[f.key];
    if (v === undefined || v === "" || (Array.isArray(v) && v.length === 0)) throw new Error(`'${f.label}'을(를) 입력하세요.`);
  }
  if (t.name === "github") for (const r of out.repos as string[]) if (!/^[\w.-]+\/[\w.-]+$/.test(r)) throw new Error(`저장소는 owner/repo 꼴이어야 합니다: ${r}`);
  if (t.name === "rss") for (const f of out.feeds as Array<{ url: string }>) if (!/^https?:\/\//.test(f.url)) throw new Error(`피드 주소는 http(s)://로 시작해야 합니다: ${f.url}`);
  return out;
}

/** Connector as the UI edits it: rss feeds back to plain URLs; everything else as stored. */
export function displayConnector(connector: Record<string, unknown> | undefined): Record<string, unknown> {
  const c = { ...(connector ?? {}) };
  if (Array.isArray(c.feeds)) c.feeds = c.feeds.map((f) => (f && typeof f === "object" ? String((f as { url?: unknown }).url ?? "") : String(f))).filter(Boolean);
  return c;
}

export type SavePatch = { enabled?: boolean; description?: string; type?: string; connector?: Record<string, unknown>; channels?: { ids?: string[]; names?: string[] } };

/**
 * Creates or updates one connection. `name` is the template, or an alias (then `type` names the
 * template on first save). Other keys in config.json are untouched. Returns the stored entry.
 */
export function saveDatasource(autoragConfig: string, name: string, patch: SavePatch): DatasourceEntry {
  if (!/^[a-z0-9][a-z0-9_-]{0,39}$/.test(name)) throw new Error("이름은 영문 소문자·숫자·-·_ 로 40자 이내여야 합니다.");
  const cfg = readConfig(autoragConfig);
  const all = readDatasources(autoragConfig);
  const prev = all[name];
  const type = patch.type ?? prev?.type;
  if (type && type === name) throw new Error("별칭 이름은 템플릿 이름과 달라야 합니다.");
  const t = templateByName(type ?? name);
  if (!t) throw new Error(`모르는 데이터소스입니다: ${type ?? name}`);
  const p = probe(t, patch.connector ?? prev?.connector ?? {});
  if (p.unavailable) throw new Error(p.unavailable);
  const next: DatasourceEntry = { ...(prev ?? {}) };
  if (type) next.type = type;
  next.enabled = patch.enabled ?? prev?.enabled ?? true;
  if (patch.description !== undefined) {
    if (patch.description.trim()) next.description = patch.description.trim();
    else delete next.description;
  }
  if (patch.connector !== undefined || !prev) next.connector = shapeConnector(t, patch.connector ?? {});
  if (patch.channels !== undefined) {
    const ids = strs(patch.channels.ids);
    const names = strs(patch.channels.names);
    if (ids.length || names.length) next.channels = { ...(ids.length ? { ids } : {}), ...(names.length ? { names } : {}) };
    else delete next.channels;
  }
  cfg.datasources = { ...((cfg.datasources as Record<string, unknown>) ?? {}), [name]: next };
  writeConfig(autoragConfig, cfg);
  return next;
}

export function removeDatasource(autoragConfig: string, name: string): boolean {
  if (!existsSync(autoragConfig)) return false;
  const cfg = readConfig(autoragConfig);
  const ds = cfg.datasources;
  if (!ds || typeof ds !== "object" || !(name in (ds as object))) return false;
  const next = { ...(ds as Record<string, unknown>) };
  delete next[name];
  if (Object.keys(next).length) cfg.datasources = next;
  else delete cfg.datasources;
  writeConfig(autoragConfig, cfg);
  return true;
}

// ── status for the API ─────────────────────────────────────────────────────────

/** What AutoRAG reports for one connection (`autorag.datasources.list`). */
export type AutoragDatasource = { datasourceId: string; name?: string; type?: string; description?: string; status?: string; sourceScopes?: string[]; tags?: string[] };

export type SyncRecord = { lastSync: string; ok: boolean; error?: string; chunks?: number };

/**
 * Per-connection outcome of a refresh that ran the `datasources` phase. AutoRAG reports
 * `datasources: [{ skill, instanceId, ok, chunkCount, indexedAt, error? }]`; a thrown refresh marks every
 * configured connection failed. `names` are the configured config keys (aliases map by their template).
 */
export function syncRecords(result: unknown, error: string | undefined, names: string[]): Record<string, SyncRecord> {
  const now = new Date().toISOString();
  const out: Record<string, SyncRecord> = {};
  if (error !== undefined) {
    for (const n of names) out[n] = { lastSync: now, ok: false, error };
    return out;
  }
  const list = (result as { datasources?: unknown })?.datasources;
  if (!Array.isArray(list)) return out;
  for (const r of list as Array<Record<string, unknown>>) {
    const skill = String(r.skill ?? "");
    const name = names.includes(skill) ? skill : names.find((n) => n === r.instanceId) ?? skill;
    if (!name) continue;
    const at = typeof r.indexedAt === "number" ? new Date(r.indexedAt).toISOString() : now;
    const diag = Array.isArray(r.diagnostics) ? (r.diagnostics as Array<{ message?: string }>).map((d) => d?.message).filter(Boolean).join("; ") : "";
    out[name] = r.ok === false ? { lastSync: at, ok: false, error: String(r.error ?? diag ?? "실패") } : { lastSync: at, ok: true, ...(typeof r.chunkCount === "number" ? { chunks: r.chunkCount } : {}) };
  }
  return out;
}

/**
 * The original file behind an external hit, for datasources that index local files: an Obsidian note
 * ("/obsidian/<instance>/<vault-relative path>") is read from the vault; others have no local original.
 */
export function readExternalFile(autoragConfig: string, source: string): { path: string; markdown: string } | null {
  const m = /^\/([^/]+)\/[^/]+\/(.+)$/.exec(source);
  if (!m) return null;
  const [, id, rel] = m;
  const entry = readDatasources(autoragConfig)[id];
  if (!entry) return null;
  const template = String(entry.type ?? id);
  if (template !== "obsidian") return null;
  const vault = String(entry.connector?.vaultPath ?? "");
  if (!vault) return null;
  const file = join(vault, ...rel.split("/").map((s) => decodeURIComponent(s)));
  if (!file.startsWith(vault + "/") || rel.split("/").includes("..")) return null;
  if (!existsSync(file) || !/\.(md|markdown|txt)$/i.test(file)) return null;
  return { path: source, markdown: readFileSync(file, "utf8") };
}

export type DatasourceStatus = {
  name: string;
  /** Template the entry is built from (= name unless an alias). */
  template: string;
  title: string;
  description: string;
  fields: DatasourceField[];
  cli: { bin: string; install: string; homepage?: string } | null;
  external: string | null;
  probe: Probe;
  configured: boolean;
  enabled: boolean;
  /** User's own note on the connection (AutoRAG shows it to the agent). */
  note: string | null;
  connector: Record<string, unknown>;
  channels: { ids?: string[]; names?: string[] } | null;
  /** What AutoRAG currently has loaded for it (null until the child is restarted after a save). */
  autorag: AutoragDatasource | null;
  sync: SyncRecord | null;
};

/** Templates first (with their config, if any), then alias entries whose template is known. */
export function listStatus(autoragConfig: string, autorag: AutoragDatasource[] | null, syncs: Record<string, SyncRecord> = {}, env: NodeJS.ProcessEnv = process.env): DatasourceStatus[] {
  const configured = readDatasources(autoragConfig);
  const seen = new Set<string>();
  const rows: DatasourceStatus[] = [];
  const row = (name: string, t: DatasourceTemplate, e: DatasourceEntry | undefined): DatasourceStatus => ({
    name,
    template: t.name,
    title: datasourceLabel(name, e?.type),
    description: t.description,
    fields: t.fields,
    cli: t.cli ?? null,
    external: t.external ?? null,
    probe: probe(t, e?.connector ?? {}, env),
    configured: e !== undefined,
    enabled: e !== undefined && e.enabled !== false,
    note: e?.description ?? null,
    connector: displayConnector(e?.connector),
    channels: e?.channels ?? null,
    autorag: autorag?.find((a) => a.datasourceId === name) ?? null,
    sync: syncs[name] ?? null,
  });
  for (const t of TEMPLATES) {
    seen.add(t.name);
    rows.push(row(t.name, t, configured[t.name]));
  }
  for (const [name, e] of Object.entries(configured)) {
    if (seen.has(name)) continue;
    const t = templateByName(String(e.type ?? ""));
    if (t) rows.push(row(name, t, e));
  }
  return rows;
}

/** Datasource ids (template names + aliases) a search hit's source path may start with. */
export function knownDatasourceIds(autoragConfig: string): string[] {
  const ids = new Set(TEMPLATES.map((t) => t.name));
  try {
    for (const k of Object.keys(readDatasources(autoragConfig))) ids.add(k);
  } catch {
    /* unreadable config: templates only */
  }
  return [...ids];
}
