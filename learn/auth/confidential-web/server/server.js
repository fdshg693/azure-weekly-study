// confidential-web — サーバーサイド Web アプリ（コンフィデンシャルクライアント / BFF）。
//
// これまでの auth プロジェクト（entra-spa-login / api-protect / app-roles-rbac）は、すべて
// **SPA ＝ パブリッククライアント**だった。ソースがブラウザで丸見えなので秘密（シークレット）を
// 持てず、Authorization Code Flow の改ざん対策に **PKCE** を使い、トークンはブラウザ
// （sessionStorage）に置いていた。
//
// 本プロジェクトはその正面の対比：**サーバーサイド Web アプリ ＝ コンフィデンシャルクライアント**。
//   - サーバーは秘密（クライアントシークレット）を秘匿できる。
//   - 認可コードフロー（Authorization Code Flow）を **サーバーで完結** させる。
//     ブラウザは認可コードを受け取るだけで、トークン交換（code → token）は **サーバーが
//     クライアントシークレットを付けて** 行う。
//   - 発行されたトークン（ID / アクセス / リフレッシュ）は **サーバーに保持** し、ブラウザには渡さない。
//     ブラウザが持つのは **セッション ID の入った httpOnly クッキー（sid）だけ**。
//   - これが **BFF（Backend for Frontend）**：フロントの前にバックエンドを一枚置き、トークンを
//     そこで握り、ブラウザにはセッションだけ渡す設計。
//
// ★ このプロジェクトの肝：
//   「PKCE で秘密なし（SPA / パブリック）」 ↔ 「クライアントシークレットで秘密あり（Web / コンフィデンシャル）」。
//   token エンドポイントへの POST に client_secret を付ける一行（下の exchangeCode 内）が、
//   パブリッククライアントには書けない「コンフィデンシャルの証」。
//
// 依存は jose（ID トークン検証）だけ。HTTP サーバは Node 組み込み（node:http）で読みやすさを優先する。
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { randomBytes, randomUUID } from 'node:crypto';
import { createRemoteJWKSet, jwtVerify } from 'jose';

// --- .env を手で読む（依存を増やさないため。sibling プロジェクトと同じ素朴なパーサ）---
//     プロジェクト直下の .env（server/ の 1 つ上）を読み、環境変数があればそちらを優先する。
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
const CLIENT_ID = env.CLIENT_ID;
const CLIENT_SECRET = env.CLIENT_SECRET; // ★ コンフィデンシャルの資格情報。ブラウザには絶対に出さない。
const PORT = Number(env.PORT ?? 3000);
const REDIRECT_URI = env.REDIRECT_URI ?? `http://localhost:${PORT}/auth/callback`;
const POST_LOGOUT = env.POST_LOGOUT_REDIRECT_URI ?? `http://localhost:${PORT}/`;
// 要求するスコープ。openid/profile/email で本人確認、User.Read で Graph を「サーバーが」叩く、
// offline_access でリフレッシュトークンも受け取る（コンフィデンシャルなら安全に保持できる）。
const SCOPES = env.SCOPES ?? 'openid profile email offline_access User.Read';

if (!TENANT_ID || !CLIENT_ID || !CLIENT_SECRET) {
  console.error('TENANT_ID / CLIENT_ID / CLIENT_SECRET が必要です（.env を用意してください。CLIENT_SECRET は task register の出力）。');
  process.exit(1);
}

// Entra v2 のエンドポイント群。
const AUTHORITY = `https://login.microsoftonline.com/${TENANT_ID}`;
const AUTHORIZE_URL = `${AUTHORITY}/oauth2/v2.0/authorize`;
const TOKEN_URL = `${AUTHORITY}/oauth2/v2.0/token`;
const LOGOUT_URL = `${AUTHORITY}/oauth2/v2.0/logout`;
const ISSUER = `${AUTHORITY}/v2.0`;
// ID トークン検証用の公開鍵集合（JWKS）。検証の作法は api-protect と同じ。
const JWKS = createRemoteJWKSet(new URL(`${AUTHORITY}/discovery/v2.0/keys`));

// --- サーバー側の状態（学習用の単一プロセス・インメモリ実装）---
//   sessions … sid（クッキー値）→ ユーザーのトークン一式。★ トークンはここ（サーバー）にだけ存在する。
//   pending  … ログイン開始時の state → nonce。callback で照合して CSRF / リプレイを防ぐ。
//   実運用では Redis 等の共有ストアにし、有効期限・サイズ管理を行う（ここでは本質ではないので最小限）。
const sessions = new Map();
const pending = new Map();

// === 小さなヘルパー ===
function redirect(res, location) {
  res.writeHead(302, { Location: location });
  res.end();
}
function sendJson(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body, null, 2));
}
function sendHtml(res, status, html) {
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(html);
}
function parseCookies(req) {
  const out = {};
  for (const part of (req.headers.cookie ?? '').split(';')) {
    const i = part.indexOf('=');
    if (i > -1) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}
function getSession(req) {
  const sid = parseCookies(req).sid;
  return sid ? sessions.get(sid) : undefined;
}

// 認可コードをトークンに交換する。★ ここが「コンフィデンシャル」の核心。
//   token エンドポイントへの POST に **client_secret を付ける**（パブリッククライアントには無いもの）。
//   この交換はブラウザを介さない **サーバー → Entra** の直接通信なので、シークレットが外に漏れない。
async function exchangeCode(code) {
  const form = new URLSearchParams({
    client_id: CLIENT_ID,
    scope: SCOPES,
    code,
    redirect_uri: REDIRECT_URI,
    grant_type: 'authorization_code',
    client_secret: CLIENT_SECRET, // ★ これが無い／間違っていると Entra は invalid_client で拒否する。
  });
  const r = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form,
  });
  const tok = await r.json();
  if (!r.ok) {
    const e = new Error(`token エンドポイントがエラー（${tok.error}）: ${tok.error_description ?? ''}`);
    e.status = 400;
    throw e;
  }
  return tok;
}

// アクセストークンが切れていれば、保持しているリフレッシュトークンで取り直す。
//   ★ リフレッシュトークンをサーバーに安全に保持できるのもコンフィデンシャルの利点
//      （SPA だとリフレッシュトークンの寿命や扱いに強い制約がある）。
async function refreshIfNeeded(session) {
  if (Date.now() < session.expiresAt - 60_000) return; // まだ有効（60 秒の余裕を見る）
  if (!session.refreshToken) return;
  const form = new URLSearchParams({
    client_id: CLIENT_ID,
    scope: SCOPES,
    grant_type: 'refresh_token',
    refresh_token: session.refreshToken,
    client_secret: CLIENT_SECRET, // リフレッシュ時もコンフィデンシャルはシークレットで認証する。
  });
  const r = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form,
  });
  const tok = await r.json();
  if (!r.ok) return; // 失敗してもここでは致命的にしない（呼び出し側が Graph 側のエラーで気づく）
  session.accessToken = tok.access_token;
  session.refreshToken = tok.refresh_token ?? session.refreshToken;
  session.expiresAt = Date.now() + (Number(tok.expires_in) || 3600) * 1000;
  console.log('  アクセストークンをリフレッシュトークンで更新しました（サーバー内で完結）。');
}

// === ルーティング ===
const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  try {
    // (1) トップページ。ログイン状態に応じて出し分ける（サーバーレンダリング）。
    if (req.method === 'GET' && url.pathname === '/') {
      return sendHtml(res, 200, renderPage(getSession(req)));
    }

    // (2) ログイン開始。state / nonce を発行して Entra の authorize へリダイレクトする。
    //     ここではトークンは一切扱わない。「ブラウザを Entra へ送り出す」だけ。
    if (req.method === 'GET' && url.pathname === '/login') {
      const state = randomBytes(16).toString('hex');
      const nonce = randomBytes(16).toString('hex');
      pending.set(state, { nonce, ts: Date.now() });
      const params = new URLSearchParams({
        client_id: CLIENT_ID,
        response_type: 'code', // ★ code（認可コード）を要求。SPA と同じ Auth Code Flow だが…
        redirect_uri: REDIRECT_URI,
        response_mode: 'query',
        scope: SCOPES,
        state,
        nonce,
      });
      // …PKCE の code_challenge は付けない。代わりに後段でシークレットを使うのがコンフィデンシャル。
      // （実運用ではコンフィデンシャルでも PKCE を併用するのが推奨。ここでは対比を明確にするため省略。）
      return redirect(res, `${AUTHORIZE_URL}?${params}`);
    }

    // (3) コールバック。Entra から認可コードを受け取り、サーバーでトークンに交換する。
    if (req.method === 'GET' && url.pathname === '/auth/callback') {
      const error = url.searchParams.get('error');
      if (error) {
        return sendHtml(res, 400, renderError(`Entra からエラー: ${error} / ${url.searchParams.get('error_description') ?? ''}`));
      }
      const code = url.searchParams.get('code');
      const state = url.searchParams.get('state');
      const tx = state && pending.get(state);
      if (!code || !tx) {
        return sendHtml(res, 400, renderError('state が一致しません（CSRF 対策）。最初からやり直してください。'));
      }
      pending.delete(state);

      // ★ サーバーがシークレット付きでトークン交換（ブラウザは関与しない）。
      const tok = await exchangeCode(code);

      // ID トークンを検証（署名 / iss / aud）し、nonce の一致も確かめる。
      //   トークンは信頼できる token エンドポイントから TLS で直接受け取っているが、
      //   多層防御として api-protect と同じ作法で検証しておく。
      const { payload } = await jwtVerify(tok.id_token, JWKS, { issuer: ISSUER, audience: CLIENT_ID });
      if (payload.nonce !== tx.nonce) {
        return sendHtml(res, 400, renderError('nonce が一致しません（リプレイ対策）。'));
      }

      // セッションを作り、トークン一式は **サーバーに** 保持する。ブラウザには sid クッキーだけ返す。
      const sid = randomUUID();
      sessions.set(sid, {
        idClaims: payload,
        accessToken: tok.access_token,
        refreshToken: tok.refresh_token, // offline_access を要求したので付いてくる
        expiresAt: Date.now() + (Number(tok.expires_in) || 3600) * 1000,
      });
      // httpOnly: JS から読めない（XSS でも盗みにくい）。SameSite=Lax: Entra からの戻り遷移でも送られる。
      res.setHeader('Set-Cookie', `sid=${sid}; HttpOnly; SameSite=Lax; Path=/`);

      // サーバー側ログ＝「トークンはここ（サーバー）にある」証拠。ブラウザの devtools には出てこない。
      console.log(
        `[session ${sid.slice(0, 8)}…] ${payload.preferred_username ?? payload.name ?? 'ユーザー'} のトークンをサーバーに保管。` +
        `（access_token: ${tok.access_token ? tok.access_token.length + '文字' : 'なし'}, ` +
        `refresh_token: ${tok.refresh_token ? 'あり' : 'なし'}）。ブラウザへは sid クッキーのみ。`
      );
      return redirect(res, '/');
    }

    // (4) 自分の情報（ID トークンのクレーム）を返す。★ トークン本体は返さない。
    if (req.method === 'GET' && url.pathname === '/api/me') {
      const s = getSession(req);
      if (!s) return sendJson(res, 401, { error: '未ログインです（/login からどうぞ）。' });
      const c = s.idClaims;
      return sendJson(res, 200, {
        message: `こんにちは、${c.name ?? c.preferred_username ?? '認証済みユーザー'} さん。`,
        'ID トークンのクレーム（サーバーが保持）': {
          name: c.name, preferred_username: c.preferred_username, oid: c.oid, tid: c.tid,
        },
        メモ: 'これは ID トークンの中身。トークン本体（生の JWT）はサーバーが握り、この応答には含めていない。',
      });
    }

    // (5) BFF の本領：サーバーが保持するアクセストークンで Graph /me を叩いて返す。
    //     ブラウザはアクセストークンを一切見ない。「ブラウザ → サーバー（cookie）→ サーバーが API を代理呼び出し」。
    if (req.method === 'GET' && url.pathname === '/api/graph') {
      const s = getSession(req);
      if (!s) return sendJson(res, 401, { error: '未ログインです（/login からどうぞ）。' });
      await refreshIfNeeded(s);
      let data;
      try {
        const r = await fetch('https://graph.microsoft.com/v1.0/me', {
          headers: { Authorization: `Bearer ${s.accessToken}` },
        });
        data = await r.json();
      } catch (e) {
        return sendJson(res, 502, { error: 'Graph 呼び出しに失敗: ' + (e.message || e) });
      }
      return sendJson(res, 200, {
        'Graph /me（サーバーがアクセストークンを使って取得）': data,
        メモ: 'アクセストークンはサーバー内だけで使った。ブラウザの Network タブにトークンは現れない（BFF）。',
      });
    }

    // (6) ログアウト。サーバーのセッションを破棄し、Entra のログアウトにも飛ばす。
    if (req.method === 'GET' && url.pathname === '/logout') {
      const sid = parseCookies(req).sid;
      if (sid) sessions.delete(sid);
      res.setHeader('Set-Cookie', 'sid=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0');
      const params = new URLSearchParams({ post_logout_redirect_uri: POST_LOGOUT });
      return redirect(res, `${LOGOUT_URL}?${params}`);
    }

    sendHtml(res, 404, renderError('not found'));
  } catch (e) {
    sendHtml(res, e.status ?? 500, renderError(e.message || String(e)));
  }
});

// === ごく小さなサーバーレンダリングのビュー ===
//   フロントは「ボタンと表示領域」だけ。MSAL.js も client config も無い点に注目：
//   ブラウザはクライアント ID もスコープも秘密も知らない。すべてサーバーが握る（BFF）。
function shell(body) {
  return `<!DOCTYPE html><html lang="ja"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>confidential-web — サーバーで秘密を持つ（BFF）</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 760px; margin: 2rem auto; padding: 0 1rem; line-height: 1.6; }
  h1 { font-size: 1.4rem; }
  #status { font-weight: bold; padding: .4rem .8rem; background: #f0f0f0; border-radius: 6px; display: inline-block; }
  .buttons { margin: 1rem 0; display: flex; gap: .5rem; flex-wrap: wrap; }
  button, a.btn { padding: .5rem 1rem; font-size: 1rem; cursor: pointer; text-decoration: none; border: 1px solid #888; border-radius: 4px; background: #fafafa; color: #111; display: inline-block; }
  pre { background: #1e1e1e; color: #d4d4d4; padding: 1rem; border-radius: 6px; overflow-x: auto; font-size: .85rem; }
  .hint { background: #fffbe6; border: 1px solid #ffe58f; padding: .6rem .9rem; border-radius: 6px; font-size: .9rem; }
</style></head><body>${body}</body></html>`;
}

function renderPage(session) {
  const intro = `<h1>サーバーで秘密を持つ ― コンフィデンシャルクライアント / BFF</h1>
<p>SPA（パブリッククライアント）は秘密を持てず PKCE を使い、トークンをブラウザに置きました。
   このサーバーサイド Web アプリは<b>クライアントシークレット</b>を持つ<b>コンフィデンシャルクライアント</b>で、
   認可コードフローを<b>サーバーで完結</b>させ、<b>トークンをブラウザに渡しません</b>。</p>
<p class="hint">ブラウザの devtools（Application → Cookies / Network）を開いてみてください。
   ブラウザが持つのは <code>sid</code> クッキー（httpOnly）だけで、<b>ID/アクセス/リフレッシュトークンはどこにもありません</b>。
   トークンはサーバーのメモリにあり、サーバーのコンソールログにだけ痕跡が出ます。</p>`;

  if (!session) {
    return shell(`${intro}
<p id="status">未ログイン</p>
<div class="buttons"><a class="btn" href="/login">ログイン（サーバー経由で Entra へ）</a></div>
<h2>出力</h2><pre id="output">「ログイン」を押してください。サーバーが Entra へリダイレクトします。</pre>`);
  }

  const name = session.idClaims.name ?? session.idClaims.preferred_username ?? 'ユーザー';
  return shell(`${intro}
<p id="status">ログイン中: ${name}</p>
<div class="buttons">
  <button id="me">自分の情報を見る（/api/me）</button>
  <button id="graph">Graph 経由で /me を取得（/api/graph）</button>
  <a class="btn" href="/logout">ログアウト</a>
</div>
<h2>出力</h2><pre id="output">ボタンを押すと、同一オリジンへ fetch します（sid クッキーが自動で付く）。
サーバーが保持するトークンを使って応答を組み立てます。</pre>
<script type="module">
  const out = document.getElementById('output');
  const show = (v) => out.textContent = typeof v === 'string' ? v : JSON.stringify(v, null, 2);
  // ★ fetch には Authorization ヘッダを付けない。アクセストークンはブラウザに無いから付けられない。
  //   同一オリジンなので sid クッキーが自動送信され、サーバーが「誰のセッションか」を判断する。
  async function call(path) {
    show('読み込み中...');
    try { show(await (await fetch(path)).json()); }
    catch (e) { show('失敗: ' + (e.message || e)); }
  }
  document.getElementById('me').onclick = () => call('/api/me');
  document.getElementById('graph').onclick = () => call('/api/graph');
</script>`);
}

function renderError(message) {
  return shell(`<h1>エラー</h1><pre>${String(message).replace(/</g, '&lt;')}</pre>
<p><a class="btn" href="/">トップへ戻る</a></p>`);
}

server.listen(PORT, () => {
  console.log(`confidential-web: http://localhost:${PORT}  （コンフィデンシャルクライアント / BFF）`);
  console.log(`  GET /            トップ（ログイン状態を表示）`);
  console.log(`  GET /login       Entra の authorize へリダイレクト（コード要求）`);
  console.log(`  GET /auth/callback  コード→トークン交換をサーバーでシークレット付きで実行`);
  console.log(`  GET /api/me      ID トークンのクレームを返す（トークン本体は返さない）`);
  console.log(`  GET /api/graph   サーバーがアクセストークンで Graph /me を代理取得（BFF）`);
  console.log(`  GET /logout      セッション破棄＋Entra ログアウト`);
  console.log(`  redirect_uri = ${REDIRECT_URI}`);
});
