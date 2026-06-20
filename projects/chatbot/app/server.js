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
const tools = require("./tools");
const { CHAT_MODELS, DEFAULT_CHAT_MODEL_ID, getChatModel } = require("./config/models");

const port = process.env.PORT || 3000;
// エンドポイントだけが環境固有値なので env から取得する。
const endpoint = process.env.AZURE_OPENAI_ENDPOINT;

// DefaultAzureCredential はローカル開発時は `az login` の資格情報、
// App Service 上ではシステム割り当てマネージド ID を自動で使用する
const credential = new DefaultAzureCredential();
const scope = "https://cognitiveservices.azure.com/.default";
const azureADTokenProvider = getBearerTokenProvider(credential, scope);

// AzureOpenAI クライアントは deployment / apiVersion をコンストラクタで固定するため、
// 選択できるモデルごとに 1 つずつ用意してキャッシュしておく（リクエスト毎の生成を避ける）。
// id -> { model: 設定, client: AzureOpenAI } のマップ。
const clientsByModelId = new Map(
  CHAT_MODELS.map((model) => [
    model.id,
    {
      model,
      client: new AzureOpenAI({
        endpoint,
        azureADTokenProvider,
        deployment: model.deployment,
        apiVersion: model.apiVersion,
      }),
    },
  ])
);

const SYSTEM_PROMPT =
  "あなたは親切で簡潔に答える日本語アシスタントです。" +
  "ユーザーが自分自身の情報（氏名・メール・部署・勤務地など）を尋ねたら、" +
  "get_user_profile ツールが使える場合はそれを呼び出して正確に答えてください。" +
  "ツールが使えない場合は、サインインすると自分の情報を取得できる旨を案内してください。" +
  "最新の情報や事実確認が必要なとき、Web 検索系のツール（Tavily）が使える場合は" +
  "それを使って調べてから答えてください。";
const MAX_HISTORY = 40;
// ツール呼び出し → 結果を返して再生成、のループ上限（暴走防止）。
const MAX_TOOL_ROUNDS = 5;

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
    // チャットのプロフィールツールは OBO サインイン（initialToken）を使う
    oboSignedIn: Boolean(req.session?.oboAccount),
    authConfigured: auth.isConfigured,
    // モデル切り替え用のドロップダウンに渡す（id と表示ラベルだけで十分）。
    chatModels: CHAT_MODELS.map((m) => ({ id: m.id, label: m.label })),
    defaultModelId: DEFAULT_CHAT_MODEL_ID,
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

  // 画面で選択されたモデルを解決する。未指定・不正な id は既定モデルにフォールバック。
  const selected = getChatModel(req.body?.model);
  const { deployment, reasoningEffort } = selected;
  const openai = clientsByModelId.get(selected.id).client;

  // Responses API の input 配列。Chat Completions の messages とほぼ同じ形だが、
  // ツール呼び出し（function_call）と結果（function_call_output）も同じ配列に積んでいく。
  const input = [{ role: "system", content: SYSTEM_PROMPT }, ...sanitized];

  // ログイン状態に応じて、この会話で AI に渡すツールを出し分ける。
  // Tavily キーを Key Vault から取得する場合があるため await する。
  const availableTools = await tools.toolsForRequest(req);

  // Responses API のリクエスト本体。reasoning は推論モデルのときだけ付ける
  // （非推論モデルに reasoning を渡すとエラーになるため）。
  const buildParams = (input) => {
    const params = { model: deployment, input, tools: availableTools };
    if (reasoningEffort) params.reasoning = { effort: reasoningEffort };
    return params;
  };

  try {
    let response = await openai.responses.create(buildParams(input));

    // モデルがツールを呼んだら実行し、結果を返して再度生成させるループ。
    for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
      const calls = response.output.filter((o) => o.type === "function_call");
      if (calls.length === 0) break;

      // モデルの出力（function_call を含む）をそのまま会話に積み戻す。
      input.push(...response.output);

      // 各ツール呼び出しを実行し、結果を function_call_output として追加。
      for (const call of calls) {
        let args = {};
        try {
          args = call.arguments ? JSON.parse(call.arguments) : {};
        } catch (_) {
          args = {};
        }
        const result = await tools.executeTool(req, call.name, args);
        console.log(`[tool] ${call.name}(${call.arguments || "{}"}) -> ${JSON.stringify(result)}`);
        input.push({
          type: "function_call_output",
          call_id: call.call_id,
          output: JSON.stringify(result),
        });
      }

      response = await openai.responses.create(buildParams(input));
    }

    // output_text は最終的なテキスト出力を結合してくれる便利プロパティ。
    const reply = response.output_text || "";
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
