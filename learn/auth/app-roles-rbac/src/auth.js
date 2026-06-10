// アプリ本体（ES モジュール）。
// 設定は authConfig.js から import する（authConfig.js はさらに config.js を import する）。
// MSAL 本体は CDN（UMD）が生やす window.msal を使う。
//
// api-protect との違いは、保護エンドポイントが「ロールで出し分けられる」点：
//   - /api/me     … 入口検証だけ（誰でも）。scp と roles を並べて表示する。
//   - /api/tasks  … GET は Tasks.Read、POST は Tasks.Write が必要。ロール次第で 200/403 が変わる。

// === 画面要素 ===
const $login = document.getElementById('login');
const $me = document.getElementById('me');
const $readTasks = document.getElementById('readTasks');
const $writeTask = document.getElementById('writeTask');
const $logout = document.getElementById('logout');
const $status = document.getElementById('status');
const $output = document.getElementById('output');

// === ヘルパー ===

function print(value) {
  $output.textContent = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
}

// JWT の payload をデコードする。※署名検証はしない。中身（クレーム）を見るだけの学習用。
// 本番のクライアントはアクセストークンの中身を解釈してはいけない（検証・解釈は宛先 API ＝ server.js の責務）。
function decodeJwt(token) {
  const payload = token.split('.')[1];
  const base64 = payload.replace(/-/g, '+').replace(/_/g, '/');
  const json = decodeURIComponent(escape(atob(base64)));
  return JSON.parse(json);
}

// === 起動処理 ===
async function main() {
  let config;
  try {
    config = await import('./authConfig.js');
  } catch (e) {
    $status.textContent = '設定がありません';
    print('.env を用意して `task config`（または `task serve`）を実行してください（TENANT_ID / SPA_CLIENT_ID / API_CLIENT_ID）。');
    return;
  }
  const { msalConfig, loginRequest, apiRequest, apiBaseUrl } = config;

  const msalInstance = new window.msal.PublicClientApplication(msalConfig);
  await msalInstance.initialize(); // MSAL v3 系は使用前に initialize() が必須

  // --- 画面状態の反映 ---

  function showAccount(account, rawIdToken) {
    $status.textContent = `ログイン中: ${account.name ?? account.username}`;
    $login.disabled = true;
    $me.disabled = false;
    $readTasks.disabled = false;
    $writeTask.disabled = false;
    $logout.disabled = false;
    const claims = rawIdToken ? decodeJwt(rawIdToken) : account.idTokenClaims;
    print({
      'アカウント': { name: account.name, username: account.username, tenantId: account.tenantId },
      'ID トークンのクレーム': claims,
      'メモ': '各ボタンは API 宛アクセストークンを取得して保護エンドポイントを叩く。roles 次第で 200/403 が変わる。',
    });
  }

  function showLoggedOut() {
    $status.textContent = '未ログイン';
    $login.disabled = false;
    $me.disabled = true;
    $readTasks.disabled = true;
    $writeTask.disabled = true;
    $logout.disabled = true;
    print('「ログイン」を押してください。');
  }

  // 自前 API 宛のアクセストークンを取得する共通処理。
  //   apiRequest.forceRefresh=true なので、ロールを出し入れした結果が毎回反映される。
  //   同意未取得などで失敗したらリダイレクトで取り直す。
  async function getApiToken() {
    const account = msalInstance.getActiveAccount();
    if (!account) { print('先にログインしてください。'); return null; }
    try {
      return await msalInstance.acquireTokenSilent(apiRequest);
    } catch (e) {
      print('サイレント取得に失敗したため、リダイレクトで取得し直します...');
      await msalInstance.acquireTokenRedirect(apiRequest);
      return null;
    }
  }

  // 保護エンドポイントを呼ぶ共通処理（method / path / body）。結果と、送ったトークンの roles/scp を表示する。
  async function callApi(method, path, note, body) {
    const res = await getApiToken();
    if (!res) return;
    let apiResult;
    try {
      const r = await fetch(`${apiBaseUrl}${path}`, {
        method,
        headers: {
          Authorization: `Bearer ${res.accessToken}`,
          ...(body ? { 'Content-Type': 'application/json' } : {}),
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      apiResult = { status: r.status, body: await r.json() };
    } catch (e) {
      print('API へ接続できませんでした。別ターミナルで `task api` が起動しているか確認してください。\n' + (e.message || e));
      return;
    }
    const decoded = decodeJwt(res.accessToken);
    print({
      '自前 API の応答': apiResult,
      '送ったトークンの scp（アプリの許可）': decoded.scp ?? 'なし',
      '送ったトークンの roles（ユーザーの役割）': decoded.roles ?? 'なし（App ロール未割り当て）',
      'メモ': note,
    });
  }

  // --- ボタンの配線 ---
  $login.addEventListener('click', () => msalInstance.loginRedirect(loginRequest));
  $logout.addEventListener('click', () => msalInstance.logoutRedirect());

  $me.addEventListener('click', () =>
    callApi('GET', '/api/me', 'このエンドポイントは入口検証だけ。ロールが無くても 200。scp と roles を見比べる。'));

  $readTasks.addEventListener('click', () =>
    callApi('GET', '/api/tasks', 'Tasks.Read を持てば 200、無ければ 403。`task assign -- Tasks.Read` で出し入れして確かめる。'));

  $writeTask.addEventListener('click', () =>
    callApi('POST', '/api/tasks',
      'Tasks.Write を持てば 201、無ければ 403。Read だけのユーザーはここで弾かれる＝認可の出し分け。',
      { title: `ブラウザから追加したタスク（${new Date().toLocaleTimeString()}）` }));

  // --- 初期表示 ---
  const result = await msalInstance.handleRedirectPromise();
  if (result && result.account) {
    msalInstance.setActiveAccount(result.account);
    showAccount(result.account, result.idToken);
    return;
  }

  const accounts = msalInstance.getAllAccounts();
  if (accounts.length > 0) {
    msalInstance.setActiveAccount(accounts[0]);
    showAccount(accounts[0]);
  } else {
    showLoggedOut();
  }
}

main().catch((e) => print('エラー: ' + (e.message || e)));
