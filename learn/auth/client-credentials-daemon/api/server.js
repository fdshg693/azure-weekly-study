// 自前 API（リソースサーバー）— このプロジェクトの相手は「ユーザー」ではなく「アプリ（デーモン）」。
//
// api-protect / app-roles-rbac では、SPA が「ユーザーの代理」で取ったトークンを受けていた。
// そのトークンには scp（委任スコープ）が乗っていた＝「アプリがユーザーの代理で要求した操作範囲」。
// 本プロジェクトのデーモンは Client Credentials Flow で「アプリ自身」として動くので、
//   - ユーザーがいない（name / preferred_username が無い）
//   - scp が無い（委任ではないから）
//   - 代わりに roles（= アプリに割り当てられた「アプリケーション許可」のロール）が乗る
// という、まったく別のトークンが届く。だから検証も scp ではなく roles を見る。
//
// 検証する 3 点：
//   1. 署名  … Entra の公開鍵（JWKS）で改ざんを確認（api-protect と同じ）
//   2. aud   … このトークンは「自前 API 宛」か（api://<API_CLIENT_ID>）（api-protect と同じ）
//   3. roles … アプリケーション許可ロール（Tasks.Process.All）を含むか（=このアプリが処理してよいか）
//
// ★ scp と roles の住み分け（auth トピックを通した整理）：
//     - scp   … 委任。「アプリがユーザーの代理で要求した操作範囲」。ユーザーがいるフローで出る。
//     - roles … app-roles-rbac ではユーザーに割り当てたロールだった。本プロジェクトでは「アプリ自身」に
//               割り当てたアプリケーション許可。ユーザーがいなくても roles は出る（idtyp=app）。
//
// 依存は jose だけ。HTTP サーバは Node 組み込み（node:http）で読みやすさを優先する。
// なお相手はブラウザではなくサーバー（デーモン）なので、CORS は不要（あえて付けない＝ブラウザ前提でないことの表れ）。
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createRemoteJWKSet, jwtVerify } from 'jose';

// --- .env を手で読む（依存を増やさないため。sibling プロジェクトと同じ素朴なパーサ）---
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

// このエンドポイントを呼ぶのに必要なアプリケーション許可ロール。
//   ★ デーモンの SP にこのロールを割り当てる（task grant）と roles に乗り、200 になる。
//     取り消す（task revoke）と roles から消え、403 になる。これが「出し入れ」の核心。
const REQUIRED_ROLE = 'Tasks.Process.All';

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

// 「処理待ちのタスク」っぽいデータ（メモリ上）。デーモンが取りに来る対象。中身は本質ではないので最小限。
const tasks = [
  { id: 1, title: '夜間バッチ：レポート集計', status: 'pending' },
  { id: 2, title: '夜間バッチ：古いログの削除', status: 'pending' },
];

function send(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body, null, 2));
}

// 【入口】署名・iss・aud・exp を検証する。失敗時は status 付きの例外を投げる。
//   api-protect の verify() とほぼ同じだが、scp は見ない（client credentials のトークンに scp は無い）。
async function authenticate(req) {
  const auth = req.headers['authorization'] ?? '';
  if (!auth.startsWith('Bearer ')) {
    // 通行証そのものが無い＝「どのアプリだか分からない」→ 401 Unauthorized。
    const e = new Error('Authorization: Bearer <token> がありません'); e.status = 401; throw e;
  }
  const token = auth.slice('Bearer '.length);
  let payload;
  try {
    ({ payload } = await jwtVerify(token, JWKS, { issuer: ISSUER, audience: AUDIENCE }));
  } catch (e) {
    const err = new Error('トークンが無効です: ' + e.message); err.status = 401; throw err;
  }
  return payload;
}

// 【認可】roles にアプリケーション許可ロールがあるか＝「このアプリが処理してよいか」。
//   割り当てが 1 つも無いと roles クレーム自体が存在しない（app-roles-rbac の挙動と同じ）。
//   ★ 401（どのアプリか不明）ではなく 403（アプリは分かるが許可が無い）になる点に注目。
function requireRole(payload, role) {
  const roles = payload.roles ?? [];
  if (!roles.includes(role)) {
    const err = new Error(
      `アプリケーション許可ロール '${role}' が必要です（このトークンの roles: ${roles.length ? roles.join(', ') : 'なし'}）。` +
      `'task grant' でデーモンのアプリに許可を与え、'task run' で取り直してください。`
    );
    err.status = 403; throw err;
  }
}

const server = createServer(async (req, res) => {
  try {
    // (A) 呼び出し元の身元を見せるだけのエンドポイント（入口検証のみ。特定ロール不要）。
    //     ここが「ユーザー不在」を体感する肝：name / preferred_username / scp が無く、
    //     idtyp=app（=アプリとしての呼び出し）、sub/oid はデーモンの SP の ID になる。
    if (req.method === 'GET' && req.url === '/api/whoami') {
      const c = await authenticate(req);
      send(res, 200, {
        message: 'この API を呼んだ「主体」の正体（ユーザーではなくアプリ）',
        'idtyp (識別子の型)': c.idtyp ?? '（v2 では出ないこともある）',
        'ユーザー名 (name)': c.name ?? 'なし（ユーザーがいないため）',
        'ユーザー名 (preferred_username)': c.preferred_username ?? 'なし（ユーザーがいないため）',
        '委任スコープ (scp)': c.scp ?? 'なし（委任ではない＝アプリ自身として動いているため）',
        'アプリの許可 (roles)': c.roles ?? 'なし（アプリケーション許可ロール未割り当て）',
        '呼び出し元アプリ (azp / appid)': c.azp ?? c.appid ?? '不明',
        '主体 (sub / oid)': { sub: c.sub, oid: c.oid },
        'メモ': 'SPA のトークンには name と scp があった。client credentials のトークンにはそれらが無く、roles だけがある。',
      });
      return;
    }

    // (B) 処理対象のタスク一覧 … アプリケーション許可ロール Tasks.Process.All が必要。
    //     grant で 200 / revoke で 403 に変わるのを観察するエンドポイント。
    if (req.method === 'GET' && req.url === '/api/tasks') {
      const c = await authenticate(req);
      requireRole(c, REQUIRED_ROLE);
      send(res, 200, { message: 'アプリケーション許可が確認できました。', 'アプリの許可 (roles)': c.roles, tasks });
      return;
    }

    send(res, 404, { error: 'not found' });
  } catch (e) {
    send(res, e.status ?? 500, { error: e.message });
  }
});

server.listen(PORT, () => {
  console.log(`自前 API: http://localhost:${PORT}  （宛先 aud: ${AUDIENCE[0]}）`);
  console.log(`  GET /api/whoami  入口検証のみ（呼び出し元がアプリであることを表示）`);
  console.log(`  GET /api/tasks   アプリケーション許可ロール '${REQUIRED_ROLE}' が必要`);
});
