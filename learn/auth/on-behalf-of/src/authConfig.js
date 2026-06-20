// MSAL（Microsoft Authentication Library）の設定。
// 値は config.js（= .env から `task config` で生成）から import する。
//   config.js が無い（.env 未設定）と、この import が失敗する。auth.js 側で捕捉して案内する。
import { APP_CONFIG } from './config.js';

// PublicClientApplication に渡す設定（SPA はパブリッククライアント）。他案と同じ。
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

// 中間 API(A) を呼ぶためのアクセストークン要求。
//   ★ SPA が要求するのは「A のスコープ」だけ（api://<A>/access_as_user）。下流 B のことは SPA は知らない。
//     B を呼ぶのは A の責務（OBO）。多段の各段は「次の段」だけ知る、という構造がここにも表れる。
//   forceRefresh: true … 学習用に毎回取り直す（consent の出し入れの結果をボタン操作で反映させるため）。
export const apiRequest = {
  scopes: [APP_CONFIG.apiScope],
  forceRefresh: true,
};

// 呼び出す中間 API(A) のベース URL（例：http://localhost:3000）。
export const apiBaseUrl = APP_CONFIG.apiBaseUrl;
