// デーモン（バッチ）— このプロジェクトの主役。「ユーザーがログインしない」認証。
//
// これまでの auth プロジェクトは全て「ユーザーがブラウザでサインインする」前提だった。
// だが夜間バッチ・常駐デーモン・CI などには人間がいない。そこで Client Credentials Flow を使う：
//   アプリ自身のクライアントシークレットだけで token エンドポイントからアクセストークンを取り、
//   そのトークンで保護 API を呼ぶ。ユーザーの同意・対話は一切無い。
//
// confidential-web で持った「クライアントシークレット」を、今度は **ユーザー不在** でアプリ自身が使う。
//   - confidential-web：ユーザーがログイン → そのユーザーの代理でトークン取得（委任 / scp）
//   - 本プロジェクト  ：ユーザー不在 → アプリ自身としてトークン取得（アプリケーション許可 / roles）
//
// 依存は jose だけ（トークンの中身を「表示」するための decodeJwt に使う。検証は API 側が JWKS で行う）。
// HTTP は Node 18+ のグローバル fetch。サーバーを立てず、走って終わる 1 本のスクリプト。
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { decodeJwt } from 'jose';

// --- .env を手で読む（sibling プロジェクトと同じ素朴なパーサ）---
function loadEnv(path) {
  const env = {};
  try {
    for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
      if (!line || line.trimStart().startsWith('#') || !line.includes('=')) continue;
      const i = line.indexOf('=');
      env[line.slice(0, i).trim()] = line.slice(i + 1).trim();
    }
  } catch { /* .env が無ければ環境変数のみで動く */ }
  return env;
}
const envPath = fileURLToPath(new URL('../.env', import.meta.url));
const env = { ...loadEnv(envPath), ...process.env };

const TENANT_ID = env.TENANT_ID;
const CLIENT_ID = env.CLIENT_ID;           // デーモン自身のアプリ（クライアント）ID
const CLIENT_SECRET = env.CLIENT_SECRET;   // デーモンの資格情報（confidential client）
const API_CLIENT_ID = env.API_CLIENT_ID;   // 呼ぶ相手＝自前 API のアプリ ID
const API_BASE = env.API_BASE ?? 'http://localhost:3000';

if (!TENANT_ID || !CLIENT_ID || !CLIENT_SECRET || !API_CLIENT_ID) {
  console.error('TENANT_ID / CLIENT_ID / CLIENT_SECRET / API_CLIENT_ID が必要です（.env を用意してください）。');
  process.exit(1);
}

// ★ Client Credentials Flow ではスコープに個別の権限名を並べられない。必ず "<リソース>/.default" を使う。
//   .default は「このアプリに（管理者同意で）静的に与えられた、このリソース宛の許可をすべて」の意味。
//   委任フロー（SPA）では access_as_user のように個別スコープを動的に要求できたが、ここはできない＝
//   「ユーザーがその場で同意する」フローではなく、「事前に管理者が与えた許可」で動くフローだから。
const TOKEN_URL = `https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token`;
const SCOPE = `api://${API_CLIENT_ID}/.default`;

// 1) トークン取得：grant_type=client_credentials。ユーザーも認可コードも無く、client_secret だけで取る。
async function getToken() {
  const body = new URLSearchParams({
    grant_type: 'client_credentials',   // ★ ユーザー不在のフロー
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,       // ★ これが資格情報。間違うと invalid_client で失敗する
    scope: SCOPE,                       // ★ .default 固定
  });
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const json = await res.json();
  if (!res.ok) {
    // 例：シークレット誤り → invalid_client、許可未付与でも token 自体は通常成功する（roles が無いだけ）
    throw new Error(`トークン取得に失敗: ${json.error} / ${json.error_description?.split('\n')[0] ?? ''}`);
  }
  return json.access_token;
}

// 取得したトークンの中身を表示する（検証ではなく学習用の覗き見。decodeJwt は署名検証をしない）。
function showToken(token) {
  const c = decodeJwt(token);
  console.log('--- 取得したアクセストークンの中身（client credentials） ---');
  console.log('  aud (宛先)            :', c.aud);
  console.log('  idtyp (識別子の型)    :', c.idtyp ?? '（出ないこともある）');
  console.log('  scp (委任スコープ)    :', c.scp ?? 'なし ← 委任ではないので無い');
  console.log('  roles (アプリの許可)  :', c.roles ?? 'なし ← grant 前は roles が出ない');
  console.log('  name (ユーザー名)     :', c.name ?? 'なし ← ユーザーがいない');
  console.log('  azp/appid (呼び出し元):', c.azp ?? c.appid);
  console.log('  sub/oid (主体)        :', c.sub, '/', c.oid, '← デーモンの SP の ID');
  console.log('');
}

// 2) 取得したトークンで保護 API を呼ぶ（Bearer 認証。ユーザーのトークンと同じ運び方）。
async function callApi(path, token) {
  const res = await fetch(`${API_BASE}${path}`, { headers: { Authorization: `Bearer ${token}` } });
  const text = await res.text();
  console.log(`GET ${path}  →  ${res.status} ${res.statusText}`);
  console.log(text);
  console.log('');
}

(async () => {
  console.log(`token endpoint: ${TOKEN_URL}`);
  console.log(`scope         : ${SCOPE}\n`);

  const token = await getToken();
  showToken(token);

  // whoami は入口検証だけ。grant の有無に関わらず 200 で、「ユーザー不在＝アプリとして呼んでいる」のを見せる。
  await callApi('/api/whoami', token);
  // tasks はアプリケーション許可ロールが必要。grant 済みなら 200、未付与/取り消し済みなら 403。
  await callApi('/api/tasks', token);

  console.log('ヒント: 403 のときは "task grant"（許可付与）→ "task run" で 200 に変わる。');
  console.log('        "task revoke"（許可取り消し）→ "task run" で 403 に戻る。これが委任 vs アプリ許可の出し入れ。');
})().catch((e) => {
  console.error('エラー:', e.message);
  process.exit(1);
});
