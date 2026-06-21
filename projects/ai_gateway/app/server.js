// ============================================================================
// AI Gateway アプリ — Express エントリポイント（PLAN.md §4 ステップ1〜3）
// ----------------------------------------------------------------------------
// 2 つの「面」を 1 アプリで公開する:
//   - データプレーン（推論）            … POST /infer                       （ステップ1）
//   - コントロールプレーン（読み取り）  … GET /deployments, /models         （ステップ2）
//   - コントロールプレーン（書き込み）  … POST /deployments, DELETE /deployments/:name（ステップ3）
// 後続ステップで管理 UI（画面）を足してこれらを 1 画面に統合する。
// ============================================================================

// ローカル開発用に app/.env を読み込む（openai-client.js が require 時に process.env を
// 読むため、それより前に dotenv を評価する）。__dirname 固定でどこから起動しても app/.env を見る。
// 既存の環境変数は上書きしないので、Azure 上（.env 不在）では何もしない。
require("dotenv").config({ path: require("path").join(__dirname, ".env") });

const express = require("express");
const inferRouter = require("./routes/infer");
const controlPlaneRouter = require("./routes/control-plane");

const port = process.env.PORT || 3000;

const app = express();
app.use(express.json({ limit: "1mb" }));

app.use("/", inferRouter); // データプレーン推論 API（POST /infer）
app.use("/", controlPlaneRouter); // コントロールプレーン読み取り API（GET /deployments, /models）

app.get("/healthz", (_req, res) => res.status(200).send("ok"));

app.listen(port, () => {
  console.log(`AI Gateway (step3: data-plane + control-plane read/write) listening on ${port}`);
});
