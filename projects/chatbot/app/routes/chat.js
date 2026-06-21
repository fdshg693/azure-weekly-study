// ============================================================================
// /chat ルート（HTTP の関心事のみ）
// ----------------------------------------------------------------------------
// 入力の取り出し・検証と、結果／エラーの JSON 整形だけを担当する。
// 会話生成そのものは chat/chat-service.js に委譲する。
// ============================================================================

const express = require("express");
const chatService = require("../chat/chat-service");

const router = express.Router();

router.post("/chat", async (req, res) => {
  const sanitized = chatService.sanitizeHistory(req.body?.messages);

  const invalid = chatService.validateHistory(sanitized);
  if (invalid) return res.status(400).json({ error: invalid });

  try {
    const reply = await chatService.generateReply({
      req,
      sanitized,
      modelId: req.body?.model,
    });
    res.json({ reply });
  } catch (err) {
    console.error("OpenAI error:", err);
    res.status(502).json({ error: "Azure OpenAI からの応答取得に失敗しました: " + (err.message || String(err)) });
  }
});

module.exports = router;
