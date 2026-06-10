// MSAL（Microsoft Authentication Library）の設定。
// 値は config.js（= .env から `task config` で生成）から import する。
//   config.js が無い（.env 未設定）と、この import が失敗する。auth.js 側で捕捉して案内する。
import { APP_CONFIG } from './config.js';

// PublicClientApplication に渡す設定（SPA はパブリッククライアント）。api-protect と同じ。
export const msalConfig = {
  auth: {
    clientId: APP_CONFIG.spaClientId,
    authority: `https://login.microsoftonline.com/${APP_CONFIG.tenantId}`,
    redirectUri: APP_CONFIG.redirectUri,
  },
  cache: {
    cacheLocation: 'sessionStorage', // 学習用：タブを閉じると消える＝挙動が分かりやすい
    storeAuthStateInCookie: false,
  },
};

// ログイン（本人確認）時に要求するスコープ。
export const loginRequest = {
  scopes: ['openid', 'profile'],
};

// 自前 API を呼ぶためのアクセストークン要求。
//   要求するのは委任スコープ（api://<API>/access_as_user）だけ。
//   ★ ロール（roles）はここで「要求」するものではない点に注意：
//     scp はクライアントが要求し同意で決まるが、roles は管理者がユーザーに割り当てるもの。
//     だから同じ apiRequest でも、ユーザーへのロール割り当て次第で発行トークンの roles が変わる。
//
//   forceRefresh: true … キャッシュを使わず毎回トークンを取り直す。
//     ロールを task assign / unassign で出し入れした結果を、ボタンを押すたびに反映させるための学習用設定。
//     （実運用では毎回リフレッシュせず、必要なときだけ取り直す。）
export const apiRequest = {
  scopes: [APP_CONFIG.apiScope],
  forceRefresh: true,
};

// 呼び出す自前 API のベース URL（例：http://localhost:3000）。
export const apiBaseUrl = APP_CONFIG.apiBaseUrl;
