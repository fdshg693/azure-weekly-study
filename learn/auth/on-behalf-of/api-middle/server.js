// 中間 API(A)（リソースサーバー兼コンフィデンシャルクライアント）— このプロジェクトの主役。
//
// A は二役を同時に演じる：
//   (1) リソースサーバー … SPA が送ってきた「A 宛」アクセストークン（aud=api://A, scp=access_as_user）を検証する。
//   (2) クライアント     … その先の下流 API(B) を「ログインしたユーザーとして」呼びたい。
//
// ここで問題になるのが **aud 境界**：A が受け取ったトークンは aud=api://A。B は aud=api://B しか受け入れない。
//   だから「受け取ったトークンをそのまま B に転送する」ことはできない（B が 401 で弾く）。
//   解決策が **On-Behalf-Of(OBO) フロー＝トークン交換**：
//     A が token エンドポイントに「このユーザートークン(assertion)を、B 宛トークンに替えてくれ」と頼む。
//     grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer ＋ A 自身の client_secret ＋ requested_token_use=on_behalf_of。
//     返ってくるのは aud=api://B でありながら、主体（name/oid）は **元のユーザーのまま** のトークン。
//
// 学べる対比（このプロジェクトの肝を 2 エンドポイントで体感する）：
//   - GET /api/chain-naive … 受け取った *ユーザートークンをそのまま* B に転送 → B が aud 不一致で 401。「転送はできない」。
//   - GET /api/chain-obo   … OBO 交換してから B を呼ぶ → 200。B の応答に元ユーザーの name が乗る。「伝播できる」。
//
// SDK は使わず、OBO 交換を fetch 1 本で露わにする（confidential-web で code→token 交換を露わにしたのと同じ流儀）。
// 依存は jose（受け取ったトークンの検証）。HTTP は Node 組み込み＋グローバル fetch。SPA(:5173) が叩くので CORS 有り。
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createRemoteJWKSet, jwtVerify } from 'jose';

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
const API_A_CLIENT_ID = env.API_A_CLIENT_ID;          // A 自身（リソースかつクライアント）
const API_A_CLIENT_SECRET = env.API_A_CLIENT_SECRET;  // A の資格情報（OBO 交換に使う）
const API_B_CLIENT_ID = env.API_B_CLIENT_ID;          // 呼ぶ相手＝下流 API(B)
const PORT = Number(env.API_A_PORT ?? 3000);
const ORIGIN = env.SPA_ORIGIN ?? 'http://localhost:5173';
const API_B_BASE = env.API_B_BASE ?? 'http://localhost:3001';
const REQUIRED_SCOPE = 'access_as_user';

if (!TENANT_ID || !API_A_CLIENT_ID || !API_A_CLIENT_SECRET || !API_B_CLIENT_ID) {
  console.error('TENANT_ID / API_A_CLIENT_ID / API_A_CLIENT_SECRET / API_B_CLIENT_ID が必要です（.env を用意してください）。');
  process.exit(1);
}

const ISSUER = `https://login.microsoftonline.com/${TENANT_ID}/v2.0`;
const JWKS = createRemoteJWKSet(new URL(`https://login.microsoftonline.com/${TENANT_ID}/discovery/v2.0/keys`));
// A が受け入れる宛先(aud) ＝ 自分（A）。SPA は api://A 宛トークンを送ってくる。
const AUDIENCE = [`api://${API_A_CLIENT_ID}`, API_A_CLIENT_ID];

const TOKEN_URL = `https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token`;
// OBO で要求する下流スコープ。委任なので個別スコープ（.default ではない）を指定できる。
const OBO_SCOPE = `api://${API_B_CLIENT_ID}/access_as_user`;

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', ORIGIN);
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
}
function send(res, status, body) {
  cors(res);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body, null, 2));
}

// 【入口】SPA から来た「A 宛」トークンを検証し、Bearer の生文字列も返す（OBO の assertion に使うため）。
async function authenticate(req) {
  const auth = req.headers['authorization'] ?? '';
  if (!auth.startsWith('Bearer ')) {
    const e = new Error('Authorization: Bearer <token> がありません'); e.status = 401; throw e;
  }
  const token = auth.slice('Bearer '.length);
  let payload;
  try {
    ({ payload } = await jwtVerify(token, JWKS, { issuer: ISSUER, audience: AUDIENCE }));
  } catch (e) {
    const err = new Error('トークンが無効です: ' + e.message); err.status = 401; throw err;
  }
  const scopes = (payload.scp ?? '').split(' ');
  if (!scopes.includes(REQUIRED_SCOPE)) {
    const err = new Error(`scope '${REQUIRED_SCOPE}' が必要です（このトークンの scp: ${payload.scp ?? 'なし'}）`);
    err.status = 403; throw err;
  }
  return { payload, token };  // token（生文字列）= OBO の assertion
}

// ★ OBO トークン交換：受け取ったユーザートークンを assertion にして、B 宛トークンを取りに行く。
//   この関数こそ本プロジェクトの核心。SDK を使わず、交換の中身（grant_type / assertion / requested_token_use）を露わにする。
async function exchangeOnBehalfOf(userToken) {
  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',  // ★ OBO（JWT ベアラー）の grant_type
    client_id: API_A_CLIENT_ID,
    client_secret: API_A_CLIENT_SECRET,                          // ★ A の資格情報（confidential client だから持てる）
    assertion: userToken,                                        // ★ 受け取ったユーザートークンそのもの
    scope: OBO_SCOPE,                                            // ★ 欲しい下流スコープ（aud=api://B になる）
    requested_token_use: 'on_behalf_of',                         // ★ 「ユーザーの代理で」交換する宣言
  });
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const json = await res.json();
  if (!res.ok) {
    // 代表例：AADSTS65001（A→B の委任同意が無い）→ 'task consent' で解消。シークレット誤りなら invalid_client。
    const err = new Error(`OBO 交換に失敗: ${json.error} / ${json.error_description?.split('\n')[0] ?? ''}`);
    err.status = 502;  // 上流から見ると「中間で外部交換に失敗した」＝ 502 が素直
    throw err;
  }
  return json.access_token;  // aud=api://B、主体は元のユーザー
}

// B を Bearer で呼ぶ共通処理。応答（status / body）をそのまま返す。
async function callDownstream(token) {
  const res = await fetch(`${API_B_BASE}/api/downstream`, { headers: { Authorization: `Bearer ${token}` } });
  let body;
  try { body = await res.json(); } catch { body = await res.text(); }
  return { status: res.status, body };
}

const server = createServer(async (req, res) => {
  if (req.method === 'OPTIONS') { cors(res); res.writeHead(204); res.end(); return; }

  try {
    // (A) 入口検証だけ。受け取ったユーザートークンの素性を見せる（aud=api://A・name・scp）。
    if (req.method === 'GET' && req.url === '/api/me') {
      const { payload } = await authenticate(req);
      send(res, 200, {
        message: `中間 API(A) に到達。ここで受け取ったのは「A 宛」のユーザートークン。`,
        '宛先 (aud)': payload.aud,
        '委任スコープ (scp)': payload.scp,
        'ユーザー (name)': payload.name ?? '（なし）',
        'ユーザー (oid)': payload.oid,
        'メモ': 'この aud は api://A。だからこのトークンのままでは aud=api://B の下流 API(B) は呼べない（次の 2 ボタンで体感）。',
      });
      return;
    }

    // (B) 【失敗を見るための実演】受け取ったユーザートークンを *そのまま* B へ転送する。
    //     aud=api://A のトークンを aud=api://B の B に投げる ＝ B 側の audience 検証で 401。
    //     「トークンはそのまま転送できない（aud が違う）」を実際に 401 で確かめるエンドポイント。
    if (req.method === 'GET' && req.url === '/api/chain-naive') {
      const { token } = await authenticate(req);
      const downstream = await callDownstream(token);  // ★ 交換せず生トークンを転送
      send(res, 200, {
        message: '【素朴な転送】受け取ったユーザートークン（aud=api://A）をそのまま B へ転送した結果。',
        '下流 API(B) の応答': downstream,
        'メモ': 'B は 401 を返したはず。aud が api://A で B 宛でないため。これが OBO が必要な理由＝aud 境界。',
      });
      return;
    }

    // (C) 【本命】OBO 交換してから B を呼ぶ。aud=api://B のトークンに作り替えるので B が受け入れる。
    if (req.method === 'GET' && req.url === '/api/chain-obo') {
      const { token } = await authenticate(req);
      const oboToken = await exchangeOnBehalfOf(token);     // ★ ここでトークン交換
      const downstream = await callDownstream(oboToken);    // 交換後トークンで B を呼ぶ
      send(res, 200, {
        message: '【OBO 交換】ユーザートークンを B 宛に交換してから呼んだ結果。B まで身元が伝播している。',
        '下流 API(B) の応答': downstream,
        'メモ': 'B の応答にある name/oid は SPA でログインした本人。A を経由しても「そのユーザーとして」呼べている。',
      });
      return;
    }

    send(res, 404, { error: 'not found' });
  } catch (e) {
    send(res, e.status ?? 500, { error: e.message });
  }
});

server.listen(PORT, () => {
  console.log(`中間 API(A): http://localhost:${PORT}  （宛先 aud: ${AUDIENCE[0]} / 許可オリジン: ${ORIGIN}）`);
  console.log(`  GET /api/me           入口検証のみ（A 宛トークンの素性を表示）`);
  console.log(`  GET /api/chain-naive  生トークンを B に転送 → 401（aud 境界の実演）`);
  console.log(`  GET /api/chain-obo    OBO 交換 → B を呼ぶ → 200（要 'task consent'）`);
  console.log(`  下流 API(B): ${API_B_BASE}  / OBO スコープ: ${OBO_SCOPE}`);
});
