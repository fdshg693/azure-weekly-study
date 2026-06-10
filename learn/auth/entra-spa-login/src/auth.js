// アプリ本体（ES モジュール）。
// 設定は authConfig.js から import する（authConfig.js はさらに config.js を import する）。
// MSAL 本体は CDN（UMD）が生やす window.msal を使う ― import ではなくグローバルだが、
// 「window. を明示」することで CDN 由来であることが一目で分かるようにする。

// === 画面要素 ===
const $login = document.getElementById('login');
const $token = document.getElementById('token');
const $logout = document.getElementById('logout');
const $status = document.getElementById('status');
const $output = document.getElementById('output');

// === ヘルパー ===

// 出力欄に表示する（オブジェクトは整形して文字列化）。
function print(value) {
  $output.textContent = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
}

// JWT の payload 部分をデコードする。※署名検証はしない。中身（クレーム）を見るだけの学習用。
// 本番アプリは ID トークン/アクセストークンを「自前でデコードして信用」してはいけない（検証は発行元/API の責務）。
function decodeJwt(token) {
  const payload = token.split('.')[1];                          // header.payload.signature の真ん中
  const base64 = payload.replace(/-/g, '+').replace(/_/g, '/'); // base64url → base64
  const json = decodeURIComponent(escape(atob(base64)));        // base64 デコード後、UTF-8 として読む
  return JSON.parse(json);
}

// === 起動処理 ===
async function main() {
  // 設定（config.js → authConfig.js）を取り込む。
  // config.js 未生成（.env 未設定）なら import が失敗するので、ここで捕捉して案内する。
  let config;
  try {
    config = await import('./authConfig.js');
  } catch (e) {
    $status.textContent = '設定がありません';
    print('.env を用意して `just config`（または `just serve`）を実行してください（CLIENT_ID / TENANT_ID / REDIRECT_URI）。');
    return; // ボタンは disabled のまま
  }
  const { msalConfig, loginRequest, graphRequest } = config;

  // MSAL インスタンス。window.msal は CDN（msal-browser）が生やしたグローバル。
  const msalInstance = new window.msal.PublicClientApplication(msalConfig);
  // MSAL v3 系では、使用前に initialize() の呼び出しが必須。
  await msalInstance.initialize();

  // --- 画面状態の反映（msalInstance を使うので main 内に置く） ---

  function showAccount(account, rawIdToken) {
    $status.textContent = `ログイン中: ${account.name ?? account.username}`;
    $login.disabled = true;
    $token.disabled = false;
    $logout.disabled = false;
    // 生のトークン文字列があればデコード、なければキャッシュ済みのクレームを使う。
    const claims = rawIdToken ? decodeJwt(rawIdToken) : account.idTokenClaims;
    print({
      'アカウント': { name: account.name, username: account.username, tenantId: account.tenantId },
      'ID トークンのクレーム': claims,
    });
  }

  function showLoggedOut() {
    $status.textContent = '未ログイン';
    $login.disabled = false;
    $token.disabled = true;
    $logout.disabled = true;
    print('「ログイン」を押してください。');
  }

  // --- ボタンの配線 ---

  // ログイン：リダイレクト方式（ポップアップではなくページ遷移）。戻り先 = redirectUri。
  $login.addEventListener('click', () => msalInstance.loginRedirect(loginRequest));

  // ログアウト：IdP 側のセッションも切る。
  $logout.addEventListener('click', () => msalInstance.logoutRedirect());

  // アクセストークン取得：ログイン済みの裏で（画面遷移なしに）Graph 用トークンを取りに行く。
  $token.addEventListener('click', async () => {
    const account = msalInstance.getActiveAccount();
    if (!account) {
      print('先にログインしてください。');
      return;
    }
    try {
      // キャッシュ／リフレッシュトークンから黙って取得を試みる。
      const res = await msalInstance.acquireTokenSilent(graphRequest);
      print({
        '取得したアクセストークン（デコード）': decodeJwt(res.accessToken),
        'メモ': 'ID トークンと比べて aud（宛先）/ scp（許可された操作）が違うことに注目。これは Graph 宛の「通行証」。',
      });
    } catch (e) {
      // 同意が未取得などでサイレント取得に失敗した場合は、リダイレクトで取り直す。
      print('サイレント取得に失敗したため、リダイレクトで同意を取得します...');
      await msalInstance.acquireTokenRedirect(graphRequest);
    }
  });

  // --- 初期表示 ---

  // リダイレクトでログインから戻ってきた直後なら、その応答をここで受け取る。
  const result = await msalInstance.handleRedirectPromise();
  if (result && result.account) {
    msalInstance.setActiveAccount(result.account);
    showAccount(result.account, result.idToken); // result.idToken は生の文字列
    return;
  }

  // 戻りではない通常表示。キャッシュに既存アカウントがあればログイン済みとして扱う。
  const accounts = msalInstance.getAllAccounts();
  if (accounts.length > 0) {
    msalInstance.setActiveAccount(accounts[0]);
    showAccount(accounts[0]); // 生トークンは無いので idTokenClaims を使う
  } else {
    showLoggedOut();
  }
}

main().catch((e) => print('エラー: ' + (e.message || e)));
