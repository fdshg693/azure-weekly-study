// ============================================================================
// コントロールプレーン ルート（PLAN.md §4 ステップ2〜3）
// ----------------------------------------------------------------------------
// データプレーン（/infer）に対する「もう一方の面」の管理 API。
//   GET    /deployments       … 作成済みデプロイ一覧（az ... deployment list 相当）  ステップ2
//   GET    /models            … デプロイ可能なベースモデル一覧（az ... list-models 相当）ステップ2
//   POST   /deployments       … デプロイ作成/更新（az ... deployment create 相当）     ステップ3
//   DELETE /deployments/:name … デプロイ削除（az ... deployment delete 相当）          ステップ3
//
// 読み取り(GET)はガードレール上も安全。書き込み(POST/DELETE)は実リソースを変更するため、
// 要 Contributor ロール。整形・ARM 呼び出しの実体は arm-client.js。
// ============================================================================

const express = require("express");
const { listDeployments, listModels, createDeployment, deleteDeployment } = require("../arm-client");

const router = express.Router();

// 作成済みデプロイの一覧。出力: { deployments: [{ deployment, model, version, state, sku, capacity }] }
router.get("/deployments", async (_req, res) => {
  try {
    res.json({ deployments: await listDeployments() });
  } catch (err) {
    console.error("デプロイ一覧取得エラー:", err);
    // 403（推論ロールしか無い等）/ 404 などをそのまま観測できるよう status を返す。
    const status = err.status || 502;
    res.status(status).json({ error: err.message || String(err), status });
  }
});

// デプロイ可能なベースモデルの一覧。出力: { models: [{ model, version, format, skus, maxCapacity }] }
router.get("/models", async (_req, res) => {
  try {
    res.json({ models: await listModels() });
  } catch (err) {
    console.error("モデル一覧取得エラー:", err);
    const status = err.status || 502;
    res.status(status).json({ error: err.message || String(err), status });
  }
});

// デプロイの作成（または更新）。
//   入力: { deployment, model, version, format?, sku?, capacity? }
//   出力: { deployment: { deployment, model, version, state, sku, capacity } }
// 作成は LRO なので state は "Accepted"/"Creating" のことがある（一覧でポーリングして確認）。
router.post("/deployments", async (req, res) => {
  const { deployment, model, version, format, sku, capacity } = req.body || {};

  // 必須項目の検証（モデル名・バージョン・デプロイ名）。format/sku/capacity は arm-client 側に既定あり。
  if (!deployment || !model || !version) {
    return res
      .status(400)
      .json({ error: "deployment / model / version は必須です（format, sku, capacity は任意）" });
  }
  if (capacity !== undefined && (!Number.isInteger(capacity) || capacity <= 0)) {
    return res.status(400).json({ error: "capacity は正の整数で指定してください（TPM 単位）" });
  }

  try {
    const created = await createDeployment({ deployment, model, version, format, sku, capacity });
    // 新規は 201 相当だが、更新もありうるため 200 で返す（state で進捗を見せる）。
    res.json({ deployment: created });
  } catch (err) {
    console.error("デプロイ作成エラー:", err);
    // 403（ロール不足）/ 409（競合）/ 429・4xx（容量/クォータ超過）などをそのまま観測できる。
    const status = err.status || 502;
    res.status(status).json({ error: err.message || String(err), status });
  }
});

// デプロイの削除。出力: { deployment, deleted: true }
router.delete("/deployments/:name", async (req, res) => {
  try {
    res.json(await deleteDeployment(req.params.name));
  } catch (err) {
    console.error("デプロイ削除エラー:", err);
    const status = err.status || 502;
    res.status(status).json({ error: err.message || String(err), status });
  }
});

module.exports = router;
