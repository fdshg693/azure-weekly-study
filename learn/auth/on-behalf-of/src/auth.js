// アプリ本体（ES モジュール）。
// 設定は authConfig.js から import する（authConfig.js はさらに config.js を import する）。
// MSAL 本体は CDN（UMD）が生やす window.msal を使う。
//
// このプロジェクトの SPA は「中間 API(A) だけ」を呼ぶ。下流 API(B) は SPA から見えない。
//   - /api/me          … A が受け取ったユーザートークンの素性（aud=api://A・name・scp）を見る。
//   - /api/chain-naive … A が生トークンをそのまま B に転送 → B が aud 不一致で 401（失敗を見る）。
//   - /api/chain-obo   … A が OBO 交換してから B を呼ぶ → 200。B の応答に元ユーザーの name が乗る（成功を見る）。
// 同じログイン・同じ A 宛トークンのまま、naive は 401・obo は 200 になる対比が学びの中心。

// === 画面要素 ===
const $login = document.getElementById('login');
const $me = document.getElementById('me');
const $naive = document.getElementById('naive');
const $obo = document.getElementById('obo');
const $logout = document.getElementById('logout');
const $status = document.getElementById('status');
const $output = document.getElementById('output');

// === ヘルパー ===

function print(value) {
  $output.textContent = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
}

// JWT の payload をデコードする。※署名検証はしない。中身（クレーム）を見るだけの学習用。
// 本番のクライアントはアクセストークンの中身を解釈してはいけない（検証・解釈は宛先 API の責務）。
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
    print('.env を用意して `task config`（または `task serve`）を実行してください（TENANT_ID / SPA_CLIENT_ID / API_A_CLIENT_ID）。');
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
    $naive.disabled = false;
    $obo.disabled = false;
    $logout.disabled = false;
    const claims = rawIdToken ? decodeJwt(rawIdToken) : account.idTokenClaims;
    print({
      'アカウント': { name: account.name, username: account.username, tenantId: account.tenantId },
      'ID トークンのクレーム': claims,
      'メモ': '各ボタンは「A 宛」アクセストークンを取得して A を叩く。chain-naive は 401、chain-obo は 200 になるのを見比べる。',
    });
  }

  function showLoggedOut() {
    $status.textContent = '未ログイン';
    $login.disabled = false;
    $me.disabled = true;
    $naive.disabled = true;
    $obo.disabled = true;
    $logout.disabled = true;
    print('「ログイン」を押してください。');
  }

  // 中間 API(A) 宛のアクセストークンを取得する共通処理。
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

  // A のエンドポイントを呼ぶ共通処理。結果と、送った「A 宛」トークンの aud/scp/name を表示する。
  async function callApi(path, note) {
    const res = await getApiToken();
    if (!res) return;
    let apiResult;
    try {
      const r = await fetch(`${apiBaseUrl}${path}`, { headers: { Authorization: `Bearer ${res.accessToken}` } });
      apiResult = { status: r.status, body: await r.json() };
    } catch (e) {
      print('中間 API(A) へ接続できませんでした。別ターミナルで `task api-middle`（と `task api-downstream`）が起動しているか確認してください。\n' + (e.message || e));
      return;
    }
    const decoded = decodeJwt(res.accessToken);
    print({
      '中間 API(A) の応答': apiResult,
      '送った「A 宛」トークンの aud': decoded.aud,
      '送ったトークンの scp': decoded.scp ?? 'なし',
      '送ったトークンの name': decoded.name ?? 'なし',
      'メモ': note,
    });
  }

  // --- ボタンの配線 ---
  $login.addEventListener('click', () => msalInstance.loginRedirect(loginRequest));
  $logout.addEventListener('click', () => msalInstance.logoutRedirect());

  $me.addEventListener('click', () =>
    callApi('/api/me', 'A が受け取った「A 宛」トークンの素性。aud は api://A。だからこのままでは B は呼べない。'));

  $naive.addEventListener('click', () =>
    callApi('/api/chain-naive', '生トークンをそのまま B へ転送 → B は aud 不一致で 401。これが OBO の必要性＝aud 境界。'));

  $obo.addEventListener('click', () =>
    callApi('/api/chain-obo', 'A が OBO 交換してから B を呼ぶ → 200。B の応答の name が本人なら、身元が A を越えて伝播。403/502 のときは task consent。'));

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
