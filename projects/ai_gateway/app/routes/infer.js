// ============================================================================
// /infer ルート（データプレーン推論の最小エンドポイント）— PLAN.md §4 ステップ1
// ----------------------------------------------------------------------------
// 「管理 UI」より前に、手動で 1 つだけデプロイしたモデルへ推論を通すための最小 API。
//   入力 : { "prompt": "...", "deployment"?: "gpt-4.1" }
//   出力 : { "deployment": "...", "reply": "..." }
// deployment 省略時は env の AZURE_OPENAI_DEPLOYMENT を使う。
//
// 推論は Responses API（openai.responses.create）を使う（CLAUDE.md の方針）。
// Chat Completions は非推奨のため使わない。
// ============================================================================

const express = require("express");
const { getClient } = require("../openai-client");

const router = express.Router();

// 省略時に使う既定デプロイ名（手動で 1 つだけ作ったモデル）。
const DEFAULT_DEPLOYMENT = process.env.AZURE_OPENAI_DEPLOYMENT;

router.post("/infer", async (req, res) => {
  const prompt = req.body?.prompt;
  const deployment = req.body?.deployment || DEFAULT_DEPLOYMENT;

  if (typeof prompt !== "string" || prompt.trim() === "") {
    return res.status(400).json({ error: "prompt（文字列）は必須です" });
  }
  if (!deployment) {
    return res
      .status(400)
      .json({ error: "deployment が未指定です（リクエストで渡すか AZURE_OPENAI_DEPLOYMENT を設定）" });
  }

  try {
    const openai = getClient(deployment);

    // Responses API の最小呼び出し。input には文字列をそのまま渡せる。
    // ここで model に "デプロイ名" を渡すのが Azure OpenAI の勘所
    // （クライアント生成時にも deployment を固定しているため整合する）。
    const response = await openai.responses.create({ model: deployment, input: prompt });

    // output_text は最終的なテキスト出力を結合してくれる便利プロパティ。
    res.json({ deployment, reply: response.output_text || "" });
  } catch (err) {
    console.error("Azure OpenAI 推論エラー:", err);
    // 401/403（権限）/ 404（デプロイ名違い）/ 429（容量超過）などがそのまま観測できるよう
    // status とメッセージを返す（ステップ5 の「叩いて変化を体験」に効く）。
    const status = err.status || 502;
    res.status(status).json({ error: err.message || String(err), status });
  }
});

module.exports = router;
