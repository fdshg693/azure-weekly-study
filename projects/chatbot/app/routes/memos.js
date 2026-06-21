// ============================================================================
// 全ユーザー共有メモ（手動 UI + REST）
// ----------------------------------------------------------------------------
// AI のツール呼び出しと同じ memos.js（→ Azure Function / Mock）を経由する。
// 人が手動でも AI でも同じバックエンドを操作できることを体験するための配線。
// ============================================================================

const express = require("express");
const memos = require("../memos");

const router = express.Router();

// メモ操作画面
router.get("/memos", (req, res) => {
  res.render("memos", {
    title: "共有メモ",
    // Function 経路か Mock かを画面に出して、どの構成で動いているか分かるようにする。
    isRemote: memos.isRemote,
  });
});

// 一覧
router.get("/api/memos", async (_req, res) => {
  try {
    const data = await memos.listMemos();
    res.json(data);
  } catch (err) {
    res.status(502).json({ error: "メモ一覧の取得に失敗しました: " + (err.message || String(err)) });
  }
});

// 作成
router.post("/api/memos", async (req, res) => {
  try {
    const memo = await memos.createMemo({ title: req.body?.title, body: req.body?.body });
    res.status(201).json(memo);
  } catch (err) {
    const status = err.statusCode && err.statusCode < 500 ? err.statusCode : 502;
    res.status(status).json({ error: "メモの作成に失敗しました: " + (err.message || String(err)) });
  }
});

// 更新（部分更新）
router.patch("/api/memos/:id", async (req, res) => {
  try {
    const memo = await memos.updateMemo(req.params.id, { title: req.body?.title, body: req.body?.body });
    if (!memo) return res.status(404).json({ error: "メモが見つかりません" });
    res.json(memo);
  } catch (err) {
    res.status(502).json({ error: "メモの更新に失敗しました: " + (err.message || String(err)) });
  }
});

// 削除
router.delete("/api/memos/:id", async (req, res) => {
  try {
    const result = await memos.deleteMemo(req.params.id);
    res.json(result);
  } catch (err) {
    res.status(502).json({ error: "メモの削除に失敗しました: " + (err.message || String(err)) });
  }
});

module.exports = router;
