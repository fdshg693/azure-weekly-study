// 自前 API（リソースサーバー）— 今回の主題は「認証から認可へ」。
// api-protect では「正しいトークンを持つ相手か（署名 / aud / scp）」までを見た。
// このプロジェクトはその先、「**同じログインユーザーでも、役割（ロール）によって出来ることを変える**」。
//
// 検証は 2 段に分かれる：
//   【入口（api-protect と同じ）】 そもそもこの API を呼んでよい正しいトークンか
//     1. 署名 … Entra の公開鍵（JWKS）で改ざんを確認
//     2. aud … このトークンは「自前 API 宛」か（api://<API_CLIENT_ID>）
//     3. scp … SPA が要求した委任スコープ access_as_user を含むか（=アプリがこの API を使う許可）
//   【認可（今回の新規）】 そのユーザーは「この操作」をしてよいか
//     4. roles … トークンの roles クレームに、エンドポイントが要求する App ロールがあるか
//
// ★ scp と roles の違いがこのプロジェクトの肝：
//     - scp（scope）   … 「アプリ（SPA）がユーザーの代理で要求した操作範囲」。クライアントが要求し同意で決まる。
//     - roles          … 「主体（ユーザー）に割り当てられた役割」。管理者がユーザー／グループに割り当てる。
//   同じ 1 つのアクセストークンに両方が乗りうる。前者は「アプリが何を要求したか」、後者は「人が何者か」。
//
// 依存は jose だけ。HTTP サーバは Node 組み込み（node:http）で読みやすさを優先する。
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

// 入口の委任スコープ（api-protect と同じ）。これは「アプリがこの API を呼ぶ許可」。
const REQUIRED_SCOPE = 'access_as_user';

// エンドポイントごとに要求する App ロール。ここが認可の本体。
//   - 一覧の閲覧 … Tasks.Read を持つユーザーだけ
//   - 追加       … Tasks.Write を持つユーザーだけ
// ★ ロールを別名に変える / SPA でロールを出し入れすると、同じユーザーでも 403 に変わるのを観察できる。
const ROLE_READ = 'Tasks.Read';
const ROLE_WRITE = 'Tasks.Write';

if (!TENANT_ID || !API_CLIENT_ID) {
  console.error('TENANT_ID と API_CLIENT_ID が必要です（.env を用意してください）。');
  process.exit(1);
}

// Entra v2 エンドポイントの「発行者(iss)」と「公開鍵(JWKS)」。
//   register で requestedAccessTokenVersion=2 にしているため、トークンは v2（iss は .../v2.0）。
const ISSUER = `https://login.microsoftonline.com/${TENANT_ID}/v2.0`;
const JWKS = createRemoteJWKSet(new URL(`https://login.microsoftonline.com/${TENANT_ID}/discovery/v2.0/keys`));
// 期待する宛先(aud)。v2 のカスタム API では Application ID URI 形式 api://<appId> になる。
// （環境により GUID 形式になることもあるため両方を許容しておく）
const AUDIENCE = [`api://${API_CLIENT_ID}`, API_CLIENT_ID];

// 学習用のごく単純な「タスク」データ（メモリ上）。認可で守る対象の中身は本質ではないので最小限。
const tasks = [
  { id: 1, title: 'Entra のアプリ登録を理解する' },
  { id: 2, title: 'scp と roles の違いを説明できるようにする' },
];
let nextId = 3;

// CORS：SPA は別オリジン（:5173）なので明示的に許可する。
//   追加(POST)も使うため、許可メソッドに POST を含める。
function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', ORIGIN);
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
}
function send(res, status, body) {
  cors(res);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body, null, 2));
}

// 【入口】署名・iss・aud・exp・scp を検証する。失敗時は status 付きの例外を投げる。
//   ここまでは api-protect と同じ＝「この API を呼んでよい正しいトークンか」。
async function authenticate(req) {
  const auth = req.headers['authorization'] ?? '';
  if (!auth.startsWith('Bearer ')) {
    // 通行証そのものが無い＝「誰だか分からない」→ 401 Unauthorized。
    const e = new Error('Authorization: Bearer <token> がありません'); e.status = 401; throw e;
  }
  const token = auth.slice('Bearer '.length);
  let payload;
  try {
    ({ payload } = await jwtVerify(token, JWKS, { issuer: ISSUER, audience: AUDIENCE }));
  } catch (e) {
    const err = new Error('トークンが無効です: ' + e.message); err.status = 401; throw err;
  }
  // scp（アプリがこの API を呼ぶ許可）が無ければ、そもそも入口で弾く（403）。
  const scopes = (payload.scp ?? '').split(' ');
  if (!scopes.includes(REQUIRED_SCOPE)) {
    const err = new Error(`scope '${REQUIRED_SCOPE}' が必要です（このトークンの scp: ${payload.scp ?? 'なし'}）`);
    err.status = 403; throw err;
  }
  return payload;
}

// 【認可】roles クレームに必要な App ロールがあるか＝「このユーザーがこの操作をしてよいか」。
//   v2 トークンの roles は配列。割り当てが 1 つも無いと roles クレーム自体が存在しない。
//   ★ 401（誰か不明）ではなく 403（誰かは分かるが権限不足）になる点に注目。
function requireRole(payload, role) {
  const roles = payload.roles ?? [];
  if (!roles.includes(role)) {
    const err = new Error(
      `App ロール '${role}' が必要です（このユーザーの roles: ${roles.length ? roles.join(', ') : 'なし'}）。` +
      `'task assign -- ${role}' で割り当て、SPA で再取得してください。`
    );
    err.status = 403; throw err;
  }
}

// リクエストボディ（JSON）を読む小さなヘルパー。
function readJson(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (c) => (data += c));
    req.on('end', () => { try { resolve(JSON.parse(data || '{}')); } catch { resolve({}); } });
  });
}

const server = createServer(async (req, res) => {
  if (req.method === 'OPTIONS') { cors(res); res.writeHead(204); res.end(); return; } // CORS プリフライト

  try {
    // (A) 自分の権限を確認するエンドポイント。入口検証だけ通れば誰でも呼べる（特定ロール不要）。
    //     scp と roles を並べて返すので、「アプリの許可（scp）」と「ユーザーの役割（roles）」の
    //     違いを 1 つのトークンの中で見比べられる。
    if (req.method === 'GET' && req.url === '/api/me') {
      const claims = await authenticate(req);
      send(res, 200, {
        message: `こんにちは、${claims.name ?? claims.preferred_username ?? '認証済みユーザー'} さん。`,
        'アプリの許可 (scp)': claims.scp ?? 'なし',
        'あなたの役割 (roles)': claims.roles ?? 'なし（App ロール未割り当て）',
        'メモ': 'scp はアプリが要求した操作範囲、roles はあなたに割り当てられた役割。別物であることを確認する。',
      });
      return;
    }

    // (B) タスク一覧の閲覧 … Tasks.Read ロールが必要。
    if (req.method === 'GET' && req.url === '/api/tasks') {
      const claims = await authenticate(req);
      requireRole(claims, ROLE_READ);
      send(res, 200, { 'あなたの役割 (roles)': claims.roles, tasks });
      return;
    }

    // (C) タスクの追加 … Tasks.Write ロールが必要。
    //     同じログインユーザーでも、Read だけ持つ人はここで 403 になる＝認可の出し分け。
    if (req.method === 'POST' && req.url === '/api/tasks') {
      const claims = await authenticate(req);
      requireRole(claims, ROLE_WRITE);
      const body = await readJson(req);
      const title = (body.title ?? '').trim() || `新しいタスク #${nextId}`;
      const task = { id: nextId++, title };
      tasks.push(task);
      send(res, 201, { message: 'タスクを追加しました。', 追加したタスク: task, tasks });
      return;
    }

    send(res, 404, { error: 'not found' });
  } catch (e) {
    send(res, e.status ?? 500, { error: e.message });
  }
});

server.listen(PORT, () => {
  console.log(`自前 API: http://localhost:${PORT}  （宛先 aud: ${AUDIENCE[0]} / 許可オリジン: ${ORIGIN}）`);
  console.log(`  GET  /api/me     入口検証のみ（scp と roles を表示）`);
  console.log(`  GET  /api/tasks  ロール '${ROLE_READ}' が必要`);
  console.log(`  POST /api/tasks  ロール '${ROLE_WRITE}' が必要`);
});
