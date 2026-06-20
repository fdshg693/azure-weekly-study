// ローカル開発用に app/.env から環境変数を読み込む（最優先で実行）。
// auth.js / auth_obo.js は require された時点で process.env を読むため、
// それらを require する前に必ず dotenv を評価しておく必要がある。
// __dirname 固定なので、どのディレクトリから起動しても app/.env を参照する。
// 既存の環境変数は上書きしないため、App Service 上（.env 不在）では何もしない。
require("dotenv").config({ path: require("path").join(__dirname, ".env") });

const express = require("express");
const session = require("express-session");
const { AzureOpenAI } = require("openai");
const { getBearerTokenProvider, DefaultAzureCredential } = require("@azure/identity");
const auth = require("./auth");
const authObo = require("./auth_obo");

const port = process.env.PORT || 3000;
const endpoint = process.env.AZURE_OPENAI_ENDPOINT;
const deployment = process.env.AZURE_OPENAI_DEPLOYMENT || "gpt-4o-mini";
const apiVersion = process.env.AZURE_OPENAI_API_VERSION || "2024-10-21";

// DefaultAzureCredential はローカル開発時は `az login` の資格情報、
// App Service 上ではシステム割り当てマネージド ID を自動で使用する
const credential = new DefaultAzureCredential();
const scope = "https://cognitiveservices.azure.com/.default";
const azureADTokenProvider = getBearerTokenProvider(credential, scope);

const openai = new AzureOpenAI({ endpoint, azureADTokenProvider, deployment, apiVersion });

const SYSTEM_PROMPT = "あなたは親切で簡潔に答える日本語アシスタントです。";
const MAX_HISTORY = 40;

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

app.get("/", (req, res) => {
  res.render("index", {
    title: "Azure OpenAI Chatbot",
    signedIn: Boolean(req.session?.account),
    authConfigured: auth.isConfigured,
  });
});

// Entra ID + Microsoft Graph 認証フロー
app.get("/auth/signin", auth.signin);
app.get("/auth/redirect", auth.redirect);
app.get("/auth/signout", auth.signout);
app.get("/profile", auth.profile);

// OBO（On-Behalf-Of）フロー: 別エンドポイントで共存
app.get("/auth/signin-obo", authObo.signin);
app.get("/auth/redirect-obo", authObo.redirect);
app.get("/profile-obo", authObo.profile);
app.post("/profile-obo/fail-test", authObo.failTest);

app.post("/chat", async (req, res) => {
  const history = Array.isArray(req.body?.messages) ? req.body.messages : [];
  const sanitized = history
    .filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
    .slice(-MAX_HISTORY)
    .map((m) => ({ role: m.role, content: m.content }));

  if (sanitized.length === 0 || sanitized[sanitized.length - 1].role !== "user") {
    return res.status(400).json({ error: "最後のメッセージは user である必要があります" });
  }

  try {
    const result = await openai.chat.completions.create({
      model: deployment,
      messages: [{ role: "system", content: SYSTEM_PROMPT }, ...sanitized],
    });
    const reply = result.choices[0]?.message?.content || "";
    res.json({ reply });
  } catch (err) {
    console.error("OpenAI error:", err);
    res.status(502).json({ error: "Azure OpenAI からの応答取得に失敗しました: " + (err.message || String(err)) });
  }
});

app.get("/healthz", (_req, res) => res.status(200).send("ok"));

app.listen(port, () => {
  console.log(`listening on ${port}`);
});
