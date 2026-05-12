// On-Behalf-Of (OBO) フローのデモ実装。
// 既存の auth.js は「ユーザーがサインインして受け取ったトークンを直接 Graph に投げる」だけ。
// こちらは「ユーザーがアプリの api://<client-id>/access_as_user スコープでサインイン →
// サーバー側で OBO 交換して Graph スコープのトークンを取得 → Graph 呼び出し」の 3 段構成。
//
// テスト容易性: 初回トークンと OBO 後トークンの両方の JWT クレームを画面 + ログに出力し、
// aud が api://<client-id> → https://graph.microsoft.com に変わることを目視確認できる。

const axios = require("axios");
const { msalInstance, CLIENT_ID, GRAPH_API_ENDPOINT, isConfigured } = require("./auth");

const REDIRECT_URI_OBO =
  process.env.REDIRECT_URI_OBO ||
  (process.env.REDIRECT_URI
    ? process.env.REDIRECT_URI.replace(/\/auth\/redirect$/, "/auth/redirect-obo")
    : "http://localhost:3000/auth/redirect-obo");

const APP_API_SCOPE = CLIENT_ID ? `api://${CLIENT_ID}/access_as_user` : "";
const GRAPH_SCOPES = ["User.Read"];

function decodeJwtPayload(jwt) {
  if (typeof jwt !== "string") return null;
  const parts = jwt.split(".");
  if (parts.length < 2) return null;
  try {
    return JSON.parse(Buffer.from(parts[1], "base64url").toString());
  } catch (_) {
    return null;
  }
}

function requireConfigured(res) {
  if (isConfigured && CLIENT_ID) return true;
  res.status(503).send(
    "Entra ID 認証が未設定です。CLIENT_ID / CLIENT_SECRET / TENANT_ID を App Settings に設定し、" +
      "App Registration で api://<client-id>/access_as_user スコープを公開してください。"
  );
  return false;
}

async function signin(req, res) {
  if (!requireConfigured(res)) return;
  try {
    const authUrl = await msalInstance.getAuthCodeUrl({
      scopes: [APP_API_SCOPE],
      redirectUri: REDIRECT_URI_OBO,
    });
    res.redirect(authUrl);
  } catch (err) {
    console.error("[obo] getAuthCodeUrl error:", err);
    res.status(500).send("認証 URL の生成に失敗しました: " + (err.message || String(err)));
  }
}

async function redirect(req, res) {
  if (!requireConfigured(res)) return;
  const code = req.query.code;
  if (!code) return res.status(400).send("認可コードが見つかりません");
  try {
    const tokenResponse = await msalInstance.acquireTokenByCode({
      code,
      scopes: [APP_API_SCOPE],
      redirectUri: REDIRECT_URI_OBO,
    });
    req.session.oboAccount = tokenResponse.account;
    req.session.oboInitialToken = tokenResponse.accessToken;
    res.redirect("/profile-obo");
  } catch (err) {
    console.error("[obo] acquireTokenByCode error:", err);
    res
      .status(500)
      .send("初回トークン取得に失敗しました（api://<client-id>/access_as_user スコープが公開されているか確認）: " + (err.message || String(err)));
  }
}

async function profile(req, res) {
  if (!isConfigured || !CLIENT_ID) {
    return res.status(503).render("profile_obo", {
      title: "プロファイル (OBO)",
      configured: false,
      account: null,
      graphUser: null,
      initialClaims: null,
      oboClaims: null,
      error: "Entra ID 認証が未設定です。App Settings を確認してください。",
    });
  }
  if (!req.session.oboInitialToken) {
    return res.redirect("/auth/signin-obo");
  }

  const initialToken = req.session.oboInitialToken;
  const initialClaims = decodeJwtPayload(initialToken);

  let oboToken;
  try {
    const oboResponse = await msalInstance.acquireTokenOnBehalfOf({
      oboAssertion: initialToken,
      scopes: GRAPH_SCOPES,
    });
    oboToken = oboResponse.accessToken;
  } catch (err) {
    console.error("[obo] acquireTokenOnBehalfOf error:", err);
    return res.status(502).render("profile_obo", {
      title: "プロファイル (OBO)",
      configured: true,
      account: req.session.oboAccount,
      graphUser: null,
      initialClaims,
      oboClaims: null,
      error:
        "OBO トークン交換に失敗しました（Expose an API の access_as_user 公開・Authorized client applications 設定・Graph User.Read 同意を確認）: " +
        (err.errorMessage || err.message || String(err)),
    });
  }

  const oboClaims = decodeJwtPayload(oboToken);

  console.log("[obo] initial token claims:", JSON.stringify(initialClaims, null, 2));
  console.log("[obo] OBO-exchanged token claims:", JSON.stringify(oboClaims, null, 2));

  try {
    const { data } = await axios.get(`${GRAPH_API_ENDPOINT}v1.0/me`, {
      headers: { Authorization: `Bearer ${oboToken}` },
    });
    res.render("profile_obo", {
      title: "プロファイル (OBO)",
      configured: true,
      account: req.session.oboAccount,
      graphUser: data,
      initialClaims,
      oboClaims,
      error: null,
    });
  } catch (err) {
    console.error("[obo] Graph /me error:", err.response?.data || err.message);
    res.status(502).render("profile_obo", {
      title: "プロファイル (OBO)",
      configured: true,
      account: req.session.oboAccount,
      graphUser: null,
      initialClaims,
      oboClaims,
      error: "Graph API 呼び出しに失敗しました: " + (err.message || String(err)),
    });
  }
}

// OBO がちゃんと Entra に届いていることを確認するための失敗テスト。
// 存在しないリソースの .default スコープを要求すると Entra が AADSTS500011 系を返す。
async function failTest(req, res) {
  if (!isConfigured || !CLIENT_ID) {
    return res.status(503).json({ error: "Entra ID 認証が未設定です" });
  }
  if (!req.session.oboInitialToken) {
    return res.status(401).json({ error: "先に /auth/signin-obo でサインインしてください" });
  }
  try {
    await msalInstance.acquireTokenOnBehalfOf({
      oboAssertion: req.session.oboInitialToken,
      scopes: ["https://nonexistent.invalid/.default"],
    });
    res.json({ unexpected: "失敗するはずがなぜか成功した", note: "Entra の挙動が変わった可能性" });
  } catch (err) {
    res.status(400).json({
      errorCode: err.errorCode || null,
      errorMessage: err.errorMessage || err.message || String(err),
      subError: err.subError || null,
      correlationId: err.correlationId || null,
      note: "Entra が実際にリクエストを処理しエラーを返した証拠（AADSTS から始まるコードが見えれば OK）",
    });
  }
}

module.exports = { signin, redirect, profile, failTest };
