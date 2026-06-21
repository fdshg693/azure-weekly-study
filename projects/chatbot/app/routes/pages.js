// ============================================================================
// トップ画面 + 認証フローの配線
// ----------------------------------------------------------------------------
// チャット画面のレンダリングと、Entra ID / OBO の各認証エンドポイントを束ねる。
// 認証ロジック本体は auth.js / auth_obo.js にあり、ここは URL との対応付けのみ。
// ============================================================================

const express = require("express");
const auth = require("../auth");
const authObo = require("../auth_obo");
const { CHAT_MODELS, DEFAULT_CHAT_MODEL_ID } = require("../config/models");

const router = express.Router();

// チャット画面
router.get("/", (req, res) => {
  res.render("index", {
    title: "Azure OpenAI Chatbot",
    signedIn: Boolean(req.session?.account),
    // チャットのプロフィールツールは OBO サインイン（initialToken）を使う
    oboSignedIn: Boolean(req.session?.oboAccount),
    authConfigured: auth.isConfigured,
    // モデル切り替え用のドロップダウンに渡す（id と表示ラベルだけで十分）。
    chatModels: CHAT_MODELS.map((m) => ({ id: m.id, label: m.label })),
    defaultModelId: DEFAULT_CHAT_MODEL_ID,
  });
});

// Entra ID + Microsoft Graph 認証フロー
router.get("/auth/signin", auth.signin);
router.get("/auth/redirect", auth.redirect);
router.get("/auth/signout", auth.signout);
router.get("/profile", auth.profile);

// OBO（On-Behalf-Of）フロー: 別エンドポイントで共存
router.get("/auth/signin-obo", authObo.signin);
router.get("/auth/redirect-obo", authObo.redirect);
router.get("/profile-obo", authObo.profile);
router.post("/profile-obo/fail-test", authObo.failTest);

module.exports = router;
