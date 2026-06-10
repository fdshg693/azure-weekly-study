// 自前 API（リソースサーバー）の最小実装。
// このプロジェクトの主題：受け取った Bearer アクセストークンを「リソースサーバー側」で検証し、
// 正しいトークンを持つ相手にだけ保護リソースを返す。検証する 3 点はこれだけ：
//   1. 署名      … Entra の公開鍵（JWKS）で改ざんされていないことを確認する
//   2. aud（宛先）… このトークンは「自前 API 宛」か（api://<API_CLIENT_ID>）。前プロジェクトは Graph 宛だった
//   3. scp（範囲）… SPA が要求した委任スコープ access_as_user を含むか（=この操作をしてよいか）
// 依存は jose だけ。HTTP サーバは Node 組み込み（node:http）で済ませ、読みやすさを優先する。
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createRemoteJWKSet, jwtVerify } from 'jose';

// --- .env を手で読む（依存を増やさないため。justfile と同じ素朴なパーサ）---
//     プロジェクト直下の .env（api/ の 1 つ上）を読み、環境変数があればそちらを優先する。
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
const API_CLIENT_ID = env.API_CLIENT_ID;
const PORT = Number(env.API_PORT ?? 3000);
const ORIGIN = env.SPA_ORIGIN ?? 'http://localhost:5173';
const REQUIRED_SCOPE = 'access_as_user'; // ← 学習ステップでここを別名に変えると 403 になる

if (!TENANT_ID || !API_CLIENT_ID) {
  console.error('TENANT_ID と API_CLIENT_ID が必要です（.env を用意してください）。');
  process.exit(1);
}

// Entra v2 エンドポイントの「発行者(iss)」と「公開鍵(JWKS)」。
//   - register で requestedAccessTokenVersion=2 にしているため、トークンは v2（iss は .../v2.0）。
//   - JWKS はキー更新に追従するよう jose が裏でキャッシュ・再取得してくれる。
const ISSUER = `https://login.microsoftonline.com/${TENANT_ID}/v2.0`;
const JWKS = createRemoteJWKSet(new URL(`https://login.microsoftonline.com/${TENANT_ID}/discovery/v2.0/keys`));
// 期待する宛先(aud)。v2 のカスタム API では Application ID URI 形式 api://<appId> になる。
// （環境により GUID 形式になることもあるため両方を許容しておく）
const AUDIENCE = [`api://${API_CLIENT_ID}`, API_CLIENT_ID];

// CORS：SPA は別オリジン（:5173）なので明示的に許可する。
//   Authorization ヘッダ付きのリクエストはブラウザがプリフライト(OPTIONS)を先に送るため、それにも応える。
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

// トークン検証の本体。失敗時は status 付きの例外を投げ、呼び出し側が 401/403 に振り分ける。
async function verify(req) {
  const auth = req.headers['authorization'] ?? '';
  if (!auth.startsWith('Bearer ')) {
    // 通行証そのものが無い＝「誰だか分からない」→ 401 Unauthorized。
    const e = new Error('Authorization: Bearer <token> がありません'); e.status = 401; throw e;
  }
  const token = auth.slice('Bearer '.length);
  let payload;
  try {
    // 署名・iss・aud・期限(exp) をまとめて検証。どれか不正なら例外になる。
    ({ payload } = await jwtVerify(token, JWKS, { issuer: ISSUER, audience: AUDIENCE }));
  } catch (e) {
    const err = new Error('トークンが無効です: ' + e.message); err.status = 401; throw err;
  }
  // scp（スペース区切り）に必要なスコープがあるか＝「この操作をしてよいか」。無ければ 403 Forbidden。
  // 401（誰か分からない）と 403（誰かは分かるが権限が足りない）の違いに注目。
  const scopes = (payload.scp ?? '').split(' ');
  if (!scopes.includes(REQUIRED_SCOPE)) {
    const err = new Error(`scope '${REQUIRED_SCOPE}' が必要です（このトークンの scp: ${payload.scp ?? 'なし'}）`);
    err.status = 403; throw err;
  }
  return payload;
}

const server = createServer(async (req, res) => {
  if (req.method === 'OPTIONS') { cors(res); res.writeHead(204); res.end(); return; } // CORS プリフライト
  if (req.method === 'GET' && req.url === '/api/me') {
    try {
      const claims = await verify(req);
      send(res, 200, {
        message: `こんにちは、${claims.name ?? claims.preferred_username ?? '認証済みユーザー'} さん。保護された自前 API が応答しました。`,
        '検証に使ったクレーム': { aud: claims.aud, iss: claims.iss, scp: claims.scp, sub: claims.sub },
      });
    } catch (e) {
      send(res, e.status ?? 500, { error: e.message });
    }
    return;
  }
  send(res, 404, { error: 'not found' });
});

server.listen(PORT, () => {
  console.log(`自前 API: http://localhost:${PORT}/api/me  （宛先 aud: ${AUDIENCE[0]} / 許可オリジン: ${ORIGIN}）`);
});
