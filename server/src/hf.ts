// Speaker diarization needs a Hugging Face account that has accepted the pyannote models.
// Login is the browser device-code flow published by huggingface_hub (`hf auth login`): the app
// opens the page, the user signs in, and the token is stored here. Nothing asks the user to
// copy HF_TOKEN into the environment.

import { getSecret, setSecret } from "./rerank.ts";

/** Public client id of Hugging Face's own device-code login (`hf auth login`). */
const CLIENT_ID = process.env.HF_DEVICE_CODE_OAUTH_CLIENT_ID ?? "26be6b09-91c5-47da-9861-d2d2bb7a7e36";
const ENDPOINT = "https://huggingface.co";

/** Models whisperX loads when --diarize is on. Each one must be accepted once on the model page. */
export const DIARIZE_MODELS = ["pyannote/speaker-diarization-3.1", "pyannote/segmentation-3.0"] as const;

const ACCESS = "hf_access";
const REFRESH = "hf_refresh";
const EXPIRES = "hf_expires";
const USER = "hf_user";
const ACCEPT = "hf_accept";

export type HfLogin = { state: "pending" | "error"; userCode?: string; verificationUri?: string; error?: string };

export type HfStatus = {
  loggedIn: boolean;
  username: string | null;
  expiresAt: string | null;
  /** Gated models the account has not accepted. Diarization stays off until this is empty. */
  accept: string[];
  login: HfLogin | null;
};

type FetchLike = typeof fetch;

type Pending = {
  deviceCode: string;
  interval: number;
  deadline: number;
  view: HfLogin;
};

let pending: Pending | null = null;
let poll: Promise<void> | null = null;
let acceptCheckedAt = 0;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function expiresAt(): string | null {
  const n = Number(getSecret(EXPIRES));
  return Number.isFinite(n) && n > 0 ? new Date(n * 1000).toISOString() : null;
}

function acceptList(): string[] {
  return (getSecret(ACCEPT) ?? "").split(",").map((s) => s.trim()).filter(Boolean);
}

export function hfStatus(): HfStatus {
  const access = getSecret(ACCESS);
  return {
    loggedIn: !!access,
    username: getSecret(USER),
    expiresAt: expiresAt(),
    accept: access ? acceptList() : [],
    login: pending?.view ?? null,
  };
}

function saveToken(access: string, refresh: string | undefined, expiresIn: number | undefined, username: string): void {
  setSecret(ACCESS, access);
  setSecret(REFRESH, refresh ?? null);
  setSecret(EXPIRES, expiresIn ? String(Math.floor(Date.now() / 1000) + expiresIn) : null);
  setSecret(USER, username);
}

export function logoutHf(): HfStatus {
  pending = null;
  for (const k of [ACCESS, REFRESH, EXPIRES, USER, ACCEPT]) setSecret(k, null);
  acceptCheckedAt = 0;
  return hfStatus();
}

async function readJson(res: Response): Promise<Record<string, unknown>> {
  try {
    const v = (await res.json()) as unknown;
    return v && typeof v === "object" ? (v as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

/** Who the token belongs to. Throws when the token is rejected. */
async function whoami(token: string, fetchImpl: FetchLike): Promise<string> {
  const res = await fetchImpl(`${ENDPOINT}/api/whoami-v2`, { headers: { authorization: `Bearer ${token}` } });
  const body = await readJson(res);
  if (!res.ok || typeof body.name !== "string") throw new Error("Hugging Face가 로그인을 받아들이지 않았습니다.");
  return body.name;
}

/** Model ids that still need the user to press Agree on the model page. A network failure leaves the previous answer. */
async function checkAcceptance(token: string, fetchImpl: FetchLike): Promise<string[]> {
  const missing: string[] = [];
  for (const id of DIARIZE_MODELS) {
    const res = await fetchImpl(`${ENDPOINT}/api/models/${id}`, { headers: { authorization: `Bearer ${token}` } });
    if (res.status === 401 || res.status === 403) missing.push(id);
    else if (!res.ok) return acceptList();
  }
  setSecret(ACCEPT, missing.join(","));
  acceptCheckedAt = Date.now();
  return missing;
}

async function refreshAccess(fetchImpl: FetchLike): Promise<string | null> {
  const refresh = getSecret(REFRESH);
  const access = getSecret(ACCESS);
  if (!access) return null;
  const exp = Number(getSecret(EXPIRES));
  const due = Number.isFinite(exp) && exp > 0 && exp - Math.floor(Date.now() / 1000) < 86_400;
  if (!due) return access;
  if (!refresh) {
    logoutHf();
    return null;
  }
  const res = await fetchImpl(`${ENDPOINT}/oauth/token`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refresh, client_id: CLIENT_ID }),
  });
  const body = await readJson(res);
  if (typeof body.access_token !== "string") {
    logoutHf();
    return null;
  }
  const user = getSecret(USER) ?? (await whoami(body.access_token, fetchImpl));
  saveToken(body.access_token, typeof body.refresh_token === "string" ? body.refresh_token : refresh, typeof body.expires_in === "number" ? body.expires_in : undefined, user);
  return body.access_token;
}

/** A token that may call the diarization models, or null when login or model agreement is missing. */
export async function tokenForDiarize(fetchImpl: FetchLike = fetch): Promise<string | null> {
  const token = await refreshAccess(fetchImpl).catch(() => null);
  if (!token) return null;
  if (Date.now() - acceptCheckedAt > 10 * 60_000) await checkAcceptance(token, fetchImpl).catch(() => {});
  return acceptList().length ? null : token;
}

/**
 * Starts a browser login and returns as soon as the code is known. The token arrives in the
 * background; poll `hfStatus()` until `login` is null (success) or `login.state` is "error".
 */
export async function startHfLogin(fetchImpl: FetchLike = fetch, wait: (ms: number) => Promise<void> = sleep): Promise<HfStatus> {
  if (pending?.view.state === "pending") return hfStatus();
  const res = await fetchImpl(`${ENDPOINT}/oauth/device`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: CLIENT_ID }),
  });
  const body = await readJson(res);
  const deviceCode = typeof body.device_code === "string" ? body.device_code : "";
  const userCode = typeof body.user_code === "string" ? body.user_code : "";
  const verificationUri = typeof body.verification_uri === "string" ? body.verification_uri : `${ENDPOINT}/oauth/device`;
  const complete = typeof body.verification_uri_complete === "string" ? body.verification_uri_complete : verificationUri;
  if (!res.ok || !deviceCode || !userCode) {
    pending = { deviceCode: "", interval: 5, deadline: 0, view: { state: "error", error: "Hugging Face 로그인 페이지를 열지 못했습니다. 잠시 뒤 다시 시도하세요." } };
    return hfStatus();
  }
  const interval = Math.max(1, Number(body.interval) || 5);
  const expiresIn = Math.max(30, Number(body.expires_in) || 300);
  pending = { deviceCode, interval, deadline: Date.now() + expiresIn * 1000, view: { state: "pending", userCode, verificationUri: complete } };
  poll = watchLogin(deviceCode, interval, fetchImpl, wait);
  return hfStatus();
}

async function watchLogin(deviceCode: string, interval: number, fetchImpl: FetchLike, wait: (ms: number) => Promise<void>): Promise<void> {
  let gap = interval;
  try {
    while (pending?.view.state === "pending" && Date.now() < pending.deadline) {
      await wait(gap * 1000);
      if (pending?.view.state !== "pending") return;
      const tokenRes = await fetchImpl(`${ENDPOINT}/oauth/token`, {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:device_code", device_code: deviceCode, client_id: CLIENT_ID }),
      }).catch(() => null);
      if (!tokenRes) continue;
      const tokenBody = await readJson(tokenRes);
      if (typeof tokenBody.access_token === "string") {
        const username = await whoami(tokenBody.access_token, fetchImpl);
        saveToken(tokenBody.access_token, typeof tokenBody.refresh_token === "string" ? tokenBody.refresh_token : undefined, typeof tokenBody.expires_in === "number" ? tokenBody.expires_in : undefined, username);
        await checkAcceptance(tokenBody.access_token, fetchImpl).catch(() => {});
        pending = null;
        return;
      }
      const error = typeof tokenBody.error === "string" ? tokenBody.error : "";
      if (error === "authorization_pending") continue;
      if (error === "slow_down") {
        gap += 5;
        continue;
      }
      if (error === "access_denied") {
        pending = { deviceCode: "", interval: 5, deadline: 0, view: { state: "error", error: "로그인이 취소됐습니다." } };
        return;
      }
      if (error === "expired_token") break;
    }
    if (pending?.view.state === "pending") pending = { deviceCode: "", interval: 5, deadline: 0, view: { state: "error", error: "로그인 시간이 지났습니다. 다시 시도하세요." } };
  } catch (err) {
    pending = { deviceCode: "", interval: 5, deadline: 0, view: { state: "error", error: (err as Error).message || "로그인에 실패했습니다." } };
  } finally {
    poll = null;
  }
}

/** Re-checks the pyannote model pages after the user agrees to them. */
export async function recheckHfModels(fetchImpl: FetchLike = fetch): Promise<HfStatus> {
  const token = await refreshAccess(fetchImpl).catch(() => null);
  if (token) await checkAcceptance(token, fetchImpl);
  return hfStatus();
}

/** Resolves when the background login poll has finished (for tests). */
export function hfLoginSettled(): Promise<void> {
  return poll ?? Promise.resolve();
}
