// アプリ本体（ES モジュール）。
// 設定は authConfig.js から import する（authConfig.js はさらに config.js を import する）。
// MSAL 本体は CDN（UMD）が生やす window.msal を使う ― import ではなくグローバルだが、
// 「window. を明示」することで CDN 由来であることが一目で分かるようにする。

// === 画面要素 ===
const $login = document.getElementById('login');
const $callApi = document.getElementById('callApi');
const $callApiNoToken = document.getElementById('callApiNoToken');
const $logout = document.getElementById('logout');
const $status = document.getElementById('status');
const $output = document.getElementById('output');

// === ヘルパー ===

// 出力欄に表示する（オブジェクトは整形して文字列化）。
function print(value) {
  $output.textContent = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
}

// JWT の payload 部分をデコードする。※署名検証はしない。中身（クレーム）を見るだけの学習用。
// 本番のクライアントはアクセストークンの中身を解釈してはいけない（検証・解釈は宛先 API ＝ api/server.js の責務）。
function decodeJwt(token) {
  const payload = token.split('.')[1];                          // header.payload.signature の真ん中
  const base64 = payload.replace(/-/g, '+').replace(/_/g, '/'); // base64url → base64
  const json = decodeURIComponent(escape(atob(base64)));        // base64 デコード後、UTF-8 として読む
  return JSON.parse(json);
}

// === 起動処理 ===
async function main() {
  // 設定（config.js → authConfig.js）を取り込む。未生成（.env 未設定）なら案内して終了。
  let config;
  try {
    config = await import('./authConfig.js');
  } catch (e) {
    $status.textContent = '設定がありません';
    print('.env を用意して `just config`（または `just serve`）を実行してください（TENANT_ID / SPA_CLIENT_ID / API_CLIENT_ID）。');
    return;
  }
  const { msalConfig, loginRequest, apiRequest, apiBaseUrl } = config;

  const msalInstance = new window.msal.PublicClientApplication(msalConfig);
  await msalInstance.initialize(); // MSAL v3 系は使用前に initialize() が必須

  // --- 画面状態の反映 ---

  function showAccount(account, rawIdToken) {
    $status.textContent = `ログイン中: ${account.name ?? account.username}`;
    $login.disabled = true;
    $callApi.disabled = false;
    $callApiNoToken.disabled = false;
    $logout.disabled = false;
    const claims = rawIdToken ? decodeJwt(rawIdToken) : account.idTokenClaims;
    print({
      'アカウント': { name: account.name, username: account.username, tenantId: account.tenantId },
      'ID トークンのクレーム': claims,
      'メモ': '「自前 API を呼ぶ」を押すと、API 宛のアクセストークンを取得して保護エンドポイントを叩く。',
    });
  }

  function showLoggedOut() {
    $status.textContent = '未ログイン';
    $login.disabled = false;
    $callApi.disabled = true;
    $callApiNoToken.disabled = true;
    $logout.disabled = true;
    print('「ログイン」を押してください。');
  }

  // --- ボタンの配線 ---

  $login.addEventListener('click', () => msalInstance.loginRedirect(loginRequest));
  $logout.addEventListener('click', () => msalInstance.logoutRedirect());

  // 自前 API を呼ぶ：API 宛のアクセストークンを取得し、Bearer として保護エンドポイントに渡す。
  $callApi.addEventListener('click', async () => {
    const account = msalInstance.getActiveAccount();
    if (!account) { print('先にログインしてください。'); return; }

    // ① API 宛のアクセストークンを取得（キャッシュ／リフレッシュから黙って試みる）。
    let res;
    try {
      res = await msalInstance.acquireTokenSilent(apiRequest);
    } catch (e) {
      // 自前 API スコープへの同意が未取得などで失敗 → リダイレクトで同意を取り直す。
      print('サイレント取得に失敗したため、リダイレクトで同意を取得します...');
      await msalInstance.acquireTokenRedirect(apiRequest);
      return;
    }

    // ② 取得したトークンを Authorization: Bearer で自前 API に渡す。
    let apiResult;
    try {
      const r = await fetch(`${apiBaseUrl}/api/me`, {
        headers: { Authorization: `Bearer ${res.accessToken}` },
      });
      apiResult = { status: r.status, body: await r.json() };
    } catch (e) {
      print('API へ接続できませんでした。別ターミナルで `just api` が起動しているか確認してください。\n' + (e.message || e));
      return;
    }

    print({
      '自前 API の応答': apiResult,
      'このとき送ったアクセストークン（デコード）': decodeJwt(res.accessToken),
      'メモ': 'aud が「api://<API の ID>」= 自前 API 宛、scp に access_as_user。前プロジェクトの Graph 宛トークンと aud / scp を見比べる。',
    });
  });

  // 学習用：トークンを付けずに同じ API を叩き、リソースサーバーが 401 で弾くことを観察する。
  $callApiNoToken.addEventListener('click', async () => {
    try {
      const r = await fetch(`${apiBaseUrl}/api/me`); // Authorization ヘッダなし
      print({
        'トークン無しで呼んだ結果': { status: r.status, body: await r.json() },
        'メモ': '401 Unauthorized。リソースサーバーは「正しいトークンを持つ相手にだけ」応答する。',
      });
    } catch (e) {
      print('API へ接続できませんでした。`just api` が起動しているか確認してください。\n' + (e.message || e));
    }
  });

  // --- 初期表示 ---

  // リダイレクト（ログイン or 同意）から戻ってきた直後なら、その応答をここで受け取る。
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
