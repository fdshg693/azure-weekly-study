// MSAL（Microsoft Authentication Library）の設定。
// 値は config.js（= .env から `just config` で生成）から import する。
// → clientId / tenantId / redirectUri をコードに直書きせず、一箇所（.env）で管理するため。
//   config.js が無い（.env 未設定）と、この import が失敗する。auth.js 側で捕捉して案内する。
import { APP_CONFIG } from './config.js';

// PublicClientApplication に渡す設定。
export const msalConfig = {
  auth: {
    // アプリ登録の「アプリケーション (クライアント) ID」。どのアプリとしてログインするかを示す。
    clientId: APP_CONFIG.clientId,
    // 認可サーバー（IdP）の場所。テナント単位の URL。
    //   - <tenantId> 指定 … そのテナントのユーザーだけ（single tenant）
    //   - "common"        … 任意の組織テナント（multi tenant）。学習ステップ4で対比する。
    authority: `https://login.microsoftonline.com/${APP_CONFIG.tenantId}`,
    // ログイン後にブラウザが戻ってくる先。アプリ登録の SPA リダイレクト URI と「完全一致」が必須。
    redirectUri: APP_CONFIG.redirectUri,
  },
  cache: {
    // トークンの保管先。学習用に sessionStorage（タブを閉じると消える＝挙動が分かりやすい）。
    cacheLocation: 'sessionStorage',
    storeAuthStateInCookie: false,
  },
};

// ログイン時に要求するスコープ。
//   openid  … OpenID Connect を使う（= ID トークンを発行してもらう）合図
//   profile … 氏名などのプロフィール系クレームを ID トークンに含めてもらう
// ※ ここから profile を外すと、取得できるクレームが減ることを学習ステップ3で確認する。
export const loginRequest = {
  scopes: ['openid', 'profile'],
};

// （任意）Microsoft Graph を呼ぶためのアクセストークン要求。
// ID トークン（身分証）と違い、これは API（Graph）への「通行証」。別物であることを見比べる。
export const graphRequest = {
  scopes: ['User.Read'],
};
