// ============================================================================
// AI Gateway アプリ — Express エントリポイント（PLAN.md §4 ステップ1）
// ----------------------------------------------------------------------------
// 今はデータプレーン（推論）の最小プロキシだけを公開する。
// 後続ステップでコントロールプレーン（デプロイ一覧/作成/削除）や管理 UI を足していく。
// ============================================================================

// ローカル開発用に app/.env を読み込む（openai-client.js が require 時に process.env を
// 読むため、それより前に dotenv を評価する）。__dirname 固定でどこから起動しても app/.env を見る。
// 既存の環境変数は上書きしないので、Azure 上（.env 不在）では何もしない。
require("dotenv").config({ path: require("path").join(__dirname, ".env") });

const express = require("express");
const inferRouter = require("./routes/infer");

const port = process.env.PORT || 3000;

const app = express();
app.use(express.json({ limit: "1mb" }));

app.use("/", inferRouter); // データプレーン推論 API（POST /infer）

app.get("/healthz", (_req, res) => res.status(200).send("ok"));

app.listen(port, () => {
  console.log(`AI Gateway (step1: data-plane) listening on ${port}`);
});
