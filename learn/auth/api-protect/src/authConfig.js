// MSAL（Microsoft Authentication Library）の設定。
// 値は config.js（= .env から `just config` で生成）から import する。
//   → spaClientId / tenantId / apiScope / apiBaseUrl / redirectUri をコードに直書きせず、一箇所（.env）で管理する。
//   config.js が無い（.env 未設定）と、この import が失敗する。auth.js 側で捕捉して案内する。
import { APP_CONFIG } from './config.js';

// PublicClientApplication に渡す設定（SPA はパブリッククライアント）。
export const msalConfig = {
  auth: {
    // SPA（クライアント）側のアプリ登録の「アプリケーション (クライアント) ID」。
    // ※ 自前 API 側のアプリ登録とは別物。クライアントとリソースサーバーで登録が分かれている点が前プロジェクトとの違い。
    clientId: APP_CONFIG.spaClientId,
    authority: `https://login.microsoftonline.com/${APP_CONFIG.tenantId}`,
    redirectUri: APP_CONFIG.redirectUri,
  },
  cache: {
    cacheLocation: 'sessionStorage', // 学習用：タブを閉じると消える＝挙動が分かりやすい
    storeAuthStateInCookie: false,
  },
};

// ログイン（本人確認）時に要求するスコープ。ここは前プロジェクトと同じ。
export const loginRequest = {
  scopes: ['openid', 'profile'],
};

// 自前 API を呼ぶためのアクセストークン要求。
//   前プロジェクトは Graph の 'User.Read' を要求していた。ここでは「自前 API の委任スコープ」を要求する：
//     api://<API のクライアントID>/access_as_user
//   → 発行されるアクセストークンの aud（宛先）が「自前 API 宛」になり、scp に access_as_user が乗る。
export const apiRequest = {
  scopes: [APP_CONFIG.apiScope],
};

// 呼び出す自前 API のベース URL（例：http://localhost:3000）。
export const apiBaseUrl = APP_CONFIG.apiBaseUrl;
