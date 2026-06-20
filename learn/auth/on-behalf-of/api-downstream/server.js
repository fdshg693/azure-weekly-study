// 下流 API(B)（リソースサーバー）— 多段呼び出しの「最下流」。
//
// このプロジェクトの主題は「アイデンティティ伝播」：SPA でログインしたユーザーが、A を経由して B まで届くこと。
// B から見ると、自分を呼んできたのは A（中間 API）だが、トークンに乗っている「主体」は **元のユーザー** であってほしい。
// それを成立させるのが A 側の On-Behalf-Of 交換で、B はその結果だけを受け取って普通に検証する。
//
// だから B 自身は api-protect と同じ「ごく普通のリソースサーバー」：
//   1. 署名  … Entra の公開鍵（JWKS）で改ざんを確認
//   2. aud   … このトークンは「B 宛」か（api://<API_B_CLIENT_ID>）★ここが多段の肝
//   3. scp   … 委任スコープ access_as_user を含むか（A がユーザーの代理で要求した操作範囲）
// そして応答に「トークンが名乗っているユーザー（name / oid）」を含めることで、
//   *A を経由しても元のユーザーの身元が伝播している* ことを目に見える形で返す。
//
// ★ aud 境界の体感ポイント：
//   - SPA → A のトークンは aud=api://A。これをそのまま B に投げても、ここの audience 検証で弾かれる（401）。
//   - OBO 交換後のトークンは aud=api://B。だから B が受け入れる。「トークンはそのまま転送できない」の実物。
//
// 依存は jose だけ。HTTP サーバは Node 組み込み（node:http）。相手はブラウザではなく A（サーバー）なので CORS は不要。
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
const API_B_CLIENT_ID = env.API_B_CLIENT_ID;
const PORT = Number(env.API_B_PORT ?? 3001);
const REQUIRED_SCOPE = 'access_as_user';

if (!TENANT_ID || !API_B_CLIENT_ID) {
  console.error('TENANT_ID と API_B_CLIENT_ID が必要です（.env を用意してください）。');
  process.exit(1);
}

const ISSUER = `https://login.microsoftonline.com/${TENANT_ID}/v2.0`;
const JWKS = createRemoteJWKSet(new URL(`https://login.microsoftonline.com/${TENANT_ID}/discovery/v2.0/keys`));
// 期待する宛先(aud) ＝ 自分（B）。OBO 交換後のトークンだけがこの aud を満たす。
const AUDIENCE = [`api://${API_B_CLIENT_ID}`, API_B_CLIENT_ID];

function send(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body, null, 2));
}

// 署名・iss・aud・exp・scp を検証（api-protect / app-roles-rbac の入口と同じ）。
async function authenticate(req) {
  const auth = req.headers['authorization'] ?? '';
  if (!auth.startsWith('Bearer ')) {
    const e = new Error('Authorization: Bearer <token> がありません'); e.status = 401; throw e;
  }
  const token = auth.slice('Bearer '.length);
  let payload;
  try {
    // ★ aud が api://B でないと（＝A 宛トークンを生で転送してきた場合）ここで例外になり 401。
    ({ payload } = await jwtVerify(token, JWKS, { issuer: ISSUER, audience: AUDIENCE }));
  } catch (e) {
    const err = new Error('トークンが無効です（aud 不一致や署名・期限切れ等）: ' + e.message); err.status = 401; throw err;
  }
  const scopes = (payload.scp ?? '').split(' ');
  if (!scopes.includes(REQUIRED_SCOPE)) {
    const err = new Error(`scope '${REQUIRED_SCOPE}' が必要です（このトークンの scp: ${payload.scp ?? 'なし'}）`);
    err.status = 403; throw err;
  }
  return payload;
}

const server = createServer(async (req, res) => {
  try {
    // 下流の「本業」。OBO で受け取ったトークンを検証し、そのトークンが名乗るユーザーを応答に含める。
    //   ここで返す name / oid が SPA でログインした本人と一致する ＝ アイデンティティが A を越えて伝播した証拠。
    if (req.method === 'GET' && req.url === '/api/downstream') {
      const c = await authenticate(req);
      send(res, 200, {
        message: '下流 API(B) に到達しました。このトークンは OBO 交換でユーザーの身元を保ったまま B 宛に作り替えられたもの。',
        '宛先 (aud)': c.aud,
        '委任スコープ (scp)': c.scp,
        'トークンが名乗るユーザー (name)': c.name ?? '（なし）',
        'ユーザー (oid)': c.oid,
        '呼び出し元アプリ (azp / appid)': c.azp ?? c.appid ?? '不明',
        'メモ': 'name / oid は SPA でログインした本人のはず。azp は中間 API(A) になる＝「A が、ユーザーとして」呼んでいる。',
      });
      return;
    }

    send(res, 404, { error: 'not found' });
  } catch (e) {
    send(res, e.status ?? 500, { error: e.message });
  }
});

server.listen(PORT, () => {
  console.log(`下流 API(B): http://localhost:${PORT}  （宛先 aud: ${AUDIENCE[0]}）`);
  console.log(`  GET /api/downstream  OBO 交換後のトークン（aud=api://B）だけが通る`);
});
