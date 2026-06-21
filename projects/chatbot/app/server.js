// ローカル開発用に app/.env から環境変数を読み込む（最優先で実行）。
// auth.js / auth_obo.js / chat/openai-clients.js は require された時点で process.env を読むため、
// それらを require する前に必ず dotenv を評価しておく必要がある。
// __dirname 固定なので、どのディレクトリから起動しても app/.env を参照する。
// 既存の環境変数は上書きしないため、App Service 上（.env 不在）では何もしない。
require("dotenv").config({ path: require("path").join(__dirname, ".env") });

const express = require("express");
const session = require("express-session");

// ルーター（責務ごとに分割。dotenv 評価後に require する）。
const pagesRouter = require("./routes/pages");
const memosRouter = require("./routes/memos");
const chatRouter = require("./routes/chat");

const port = process.env.PORT || 3000;

const app = express();
app.set("view engine", "ejs");
app.set("views", __dirname + "/views");
app.use(express.json({ limit: "1mb" }));

// App Service は HTTPS 終端をフロントエンドで行うため、proxy 経由のクッキーを許可する
app.set("trust proxy", 1);

app.use(
  session({
    secret: process.env.EXPRESS_SESSION_SECRET || "dev-only-change-me",
    resave: false,
    saveUninitialized: false,
    cookie: {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
    },
  })
);

// 機能ごとのルーターをマウントする。
app.use("/", pagesRouter); // トップ画面 + 認証フロー
app.use("/", memosRouter); // 共有メモ（画面 + REST）
app.use("/", chatRouter); // チャット API

app.get("/healthz", (_req, res) => res.status(200).send("ok"));

app.listen(port, () => {
  console.log(`listening on ${port}`);
});
