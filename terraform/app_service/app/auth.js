// Microsoft Entra ID (旧 Azure AD) + MSAL Node を使った Web アプリ認証。
// 参考: https://learn.microsoft.com/en-us/entra/identity-platform/tutorial-v2-nodejs-webapp-msal
//
// 流れ:
//   1. /auth/signin       → MSAL で認可エンドポイント URL を生成しリダイレクト
//   2. /auth/redirect     → 認可コードを受け取り、トークンを取得してセッションに保存
//   3. /profile           → セッション内アクセストークンで Microsoft Graph /me を呼ぶ
//   4. /auth/signout      → ローカルセッション破棄 + Entra の logout エンドポイントへ

const msal = require("@azure/msal-node");
const axios = require("axios");

const CLOUD_INSTANCE = process.env.CLOUD_INSTANCE || "https://login.microsoftonline.com/";
const TENANT_ID = process.env.TENANT_ID || "common";
const CLIENT_ID = process.env.CLIENT_ID || "";
const CLIENT_SECRET = process.env.CLIENT_SECRET || "";
const REDIRECT_URI = process.env.REDIRECT_URI || "http://localhost:3000/auth/redirect";
const POST_LOGOUT_REDIRECT_URI = process.env.POST_LOGOUT_REDIRECT_URI || "http://localhost:3000/";
const GRAPH_API_ENDPOINT = process.env.GRAPH_API_ENDPOINT || "https://graph.microsoft.com/";

const isConfigured = Boolean(CLIENT_ID && CLIENT_SECRET);

const msalConfig = {
  auth: {
    clientId: CLIENT_ID,
    authority: `${CLOUD_INSTANCE}${TENANT_ID}`,
    clientSecret: CLIENT_SECRET,
  },
  system: {
    loggerOptions: {
      loggerCallback(_loglevel, message) {
        console.log("[msal] " + message);
      },
      piiLoggingEnabled: false,
      logLevel: msal.LogLevel.Warning,
    },
  },
};

const msalInstance = isConfigured ? new msal.ConfidentialClientApplication(msalConfig) : null;

// User.Read は Graph の /me 呼び出しに必要なデリゲート権限
const GRAPH_SCOPES = ["User.Read"];

function requireConfigured(res) {
  if (isConfigured) return true;
  res.status(503).send(
    "Entra ID 認証が未設定です。CLIENT_ID / CLIENT_SECRET / TENANT_ID / REDIRECT_URI を App Settings に設定してください。"
  );
  return false;
}

async function signin(req, res) {
  if (!requireConfigured(res)) return;
  try {
    const authUrl = await msalInstance.getAuthCodeUrl({
      scopes: GRAPH_SCOPES,
      redirectUri: REDIRECT_URI,
    });
    res.redirect(authUrl);
  } catch (err) {
    console.error("getAuthCodeUrl error:", err);
    res.status(500).send("認証 URL の生成に失敗しました: " + (err.message || String(err)));
  }
}

async function redirect(req, res) {
  if (!requireConfigured(res)) return;
  const code = req.query.code;
  if (!code) {
    return res.status(400).send("認可コードが見つかりません");
  }
  try {
    const tokenResponse = await msalInstance.acquireTokenByCode({
      code,
      scopes: GRAPH_SCOPES,
      redirectUri: REDIRECT_URI,
    });
    req.session.account = tokenResponse.account;
    req.session.accessToken = tokenResponse.accessToken;
    res.redirect("/profile");
  } catch (err) {
    console.error("acquireTokenByCode error:", err);
    res.status(500).send("トークン取得に失敗しました: " + (err.message || String(err)));
  }
}

function signout(req, res) {
  const logoutUri = `${CLOUD_INSTANCE}${TENANT_ID}/oauth2/v2.0/logout?post_logout_redirect_uri=${encodeURIComponent(
    POST_LOGOUT_REDIRECT_URI
  )}`;
  req.session.destroy(() => res.redirect(logoutUri));
}

async function profile(req, res) {
  if (!isConfigured) {
    return res.status(503).render("profile", {
      title: "プロファイル",
      configured: false,
      account: null,
      graphUser: null,
      error: "Entra ID 認証が未設定です。App Settings を確認してください。",
    });
  }
  if (!req.session.accessToken) {
    return res.redirect("/auth/signin");
  }
  try {
    const { data } = await axios.get(`${GRAPH_API_ENDPOINT}v1.0/me`, {
      headers: { Authorization: `Bearer ${req.session.accessToken}` },
    });
    res.render("profile", {
      title: "プロファイル",
      configured: true,
      account: req.session.account,
      graphUser: data,
      error: null,
    });
  } catch (err) {
    console.error("Graph /me error:", err.response?.data || err.message);
    res.status(502).render("profile", {
      title: "プロファイル",
      configured: true,
      account: req.session.account,
      graphUser: null,
      error: "Graph API 呼び出しに失敗しました: " + (err.message || String(err)),
    });
  }
}

module.exports = {
  signin,
  redirect,
  signout,
  profile,
  isConfigured,
  msalInstance,
  CLIENT_ID,
  GRAPH_API_ENDPOINT,
};
