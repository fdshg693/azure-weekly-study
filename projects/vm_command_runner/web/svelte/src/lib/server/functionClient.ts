import { DefaultAzureCredential, type AccessToken } from '@azure/identity';
import { env } from '$env/dynamic/private';

// App Service の System-Assigned MI → Function 用 AAD アプリ宛トークンを取得し、
// Function App の Easy Auth で検証させる。
//
// Function 側 Easy Auth は audience として `api://${functionAadClientId}` を受け入れる設定。
// MSAL/Identity ライブラリの scope は `<audience>/.default` 形式で要求する。

const FUNCTION_APP_URL = env.FUNCTION_APP_URL;
const FUNCTION_AAD_CLIENT_ID = env.FUNCTION_AAD_CLIENT_ID;

if (!FUNCTION_APP_URL || !FUNCTION_AAD_CLIENT_ID) {
  console.warn('[functionClient] FUNCTION_APP_URL or FUNCTION_AAD_CLIENT_ID is not set.');
}

const credential = new DefaultAzureCredential();
const scope = `api://${FUNCTION_AAD_CLIENT_ID}/.default`;

let cached: AccessToken | null = null;

async function getToken(): Promise<string> {
  const now = Date.now();
  // 1 分のバッファを取って再取得
  if (cached && cached.expiresOnTimestamp - now > 60_000) {
    return cached.token;
  }
  const token = await credential.getToken(scope);
  if (!token) throw new Error('failed to acquire AAD token');
  cached = token;
  return token.token;
}

export interface FunctionCallOptions {
  method?: 'GET' | 'POST';
  body?: unknown;
  query?: Record<string, string>;
}

export interface FunctionCallResult<T = unknown> {
  ok: boolean;
  status: number;
  data: T | { error: string };
}

export async function callFunction<T = unknown>(
  path: string,
  opts: FunctionCallOptions = {}
): Promise<FunctionCallResult<T>> {
  if (!FUNCTION_APP_URL || !FUNCTION_AAD_CLIENT_ID) {
    return { ok: false, status: 500, data: { error: 'Function URL/AAD not configured' } };
  }

  const token = await getToken();
  const url = new URL(path, FUNCTION_APP_URL);
  if (opts.query) {
    for (const [k, v] of Object.entries(opts.query)) url.searchParams.set(k, v);
  }

  const res = await fetch(url, {
    method: opts.method ?? 'GET',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined
  });

  let data: T | { error: string };
  const text = await res.text();
  try {
    data = text ? JSON.parse(text) : ({} as T);
  } catch {
    data = { error: `non-json response: ${text.slice(0, 200)}` };
  }
  return { ok: res.ok, status: res.status, data };
}
