// ============================================================================
// Chat Completions × ツール（function calling）ストリーミングのデモ CLI
// ----------------------------------------------------------------------------
// openai-node/examples/responses/streaming-tools.ts を参考にしているが、
// あちらが「Responses API + zod」なのに対し、こちらは
//   - Chat Completions API（openai.chat.completions.runTools）
//   - ユーザーの個人情報を取得するモックツール
// を使う点が異なる。
//
// runTools ヘルパーは「モデルがツールを呼ぶ → こちらの関数を実行 →
// 結果を返してモデルに続きを生成させる」というループを自動で回してくれる。
// stream: true を付けると、最終的なテキスト生成がトークン単位で流れてくる。
//
// 実行: node tools-demo.js "あなたの聞きたいこと"
//   例) node tools-demo.js "私のプランと今月の請求額は？"
// ============================================================================

// server.js と同様、ローカル開発では app/.env から環境変数を読み込む。
require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });

const { AzureOpenAI } = require("openai");
const { getBearerTokenProvider, DefaultAzureCredential } = require("@azure/identity");
const { MODELS } = require("../config/models");

// エンドポイントだけ env（環境固有）。モデル名・api-version は config/models.js から。
const endpoint = process.env.AZURE_OPENAI_ENDPOINT;
const { deployment, apiVersion } = MODELS.chat;

// DefaultAzureCredential はローカルでは `az login`、App Service 上では
// マネージド ID を自動利用する（server.js と同じ認証パターン）。
const credential = new DefaultAzureCredential();
const scope = "https://cognitiveservices.azure.com/.default";
const azureADTokenProvider = getBearerTokenProvider(credential, scope);

const openai = new AzureOpenAI({ endpoint, azureADTokenProvider, deployment, apiVersion });

// ----------------------------------------------------------------------------
// モックの「ユーザーデータベース」。
// 実運用ではここが本物の DB / API 呼び出しになる部分。
// ----------------------------------------------------------------------------
const MOCK_USERS = {
  "user-001": {
    id: "user-001",
    name: "山田 太郎",
    email: "taro.yamada@example.com",
    plan: "Pro",
    memberSince: "2023-04-01",
    address: { prefecture: "東京都", city: "千代田区" },
    billing: { currency: "JPY", currentMonthAmount: 4980, nextPaymentDate: "2026-07-01" },
  },
  "user-002": {
    id: "user-002",
    name: "佐藤 花子",
    email: "hanako.sato@example.com",
    plan: "Free",
    memberSince: "2025-11-15",
    address: { prefecture: "大阪府", city: "北区" },
    billing: { currency: "JPY", currentMonthAmount: 0, nextPaymentDate: null },
  },
};

// このデモでは「ログイン中のユーザー」を固定で擬似的に表すために使う。
// 実運用ではセッションや認証トークンから解決する。
const CURRENT_USER_ID = "user-001";

// ----------------------------------------------------------------------------
// ツールの実体となる関数。runTools がモデルの指示に応じて呼び出す。
// fields を指定すると、その項目だけを返す（不要な個人情報を渡さない練習）。
// ----------------------------------------------------------------------------
async function getUserProfile({ user_id, fields }) {
  const id = user_id || CURRENT_USER_ID;
  const user = MOCK_USERS[id];
  if (!user) {
    return { error: `ユーザー ${id} は見つかりませんでした` };
  }
  if (Array.isArray(fields) && fields.length > 0) {
    const picked = {};
    for (const f of fields) {
      if (f in user) picked[f] = user[f];
    }
    return { id: user.id, ...picked };
  }
  return user;
}

// ----------------------------------------------------------------------------
// runTools に渡すツール定義。
// function: 実際に呼ばれる JS 関数、parse: 引数文字列のパーサ。
// ----------------------------------------------------------------------------
const tools = [
  {
    type: "function",
    function: {
      name: "get_user_profile",
      description:
        "ログイン中ユーザー（または指定 user_id）の個人情報・契約プラン・請求情報を取得する。" +
        "名前・メール・住所・プラン・今月の請求額などを答える際に使う。",
      parameters: {
        type: "object",
        properties: {
          user_id: {
            type: "string",
            description: "対象ユーザーの ID。省略時はログイン中ユーザーを対象にする。",
          },
          fields: {
            type: "array",
            items: {
              type: "string",
              enum: ["name", "email", "plan", "memberSince", "address", "billing"],
            },
            description: "取得したい項目だけを絞り込みたい場合に指定する。省略時は全項目。",
          },
        },
        required: [],
      },
      function: getUserProfile,
      parse: JSON.parse,
    },
  },
];

const SYSTEM_PROMPT =
  "あなたは親切で簡潔に答える日本語アシスタントです。" +
  "ユーザー自身の情報（名前・プラン・請求など）を聞かれたら get_user_profile ツールを使って正確に答えてください。";

async function main() {
  const userMessage =
    process.argv.slice(2).join(" ").trim() || "私の名前と契約プラン、今月の請求額を教えて。";

  console.log(`\n🧑 ユーザー: ${userMessage}\n`);
  console.log("🤖 アシスタント: ");

  const runner = openai.chat.completions
    .runTools({
      model: deployment,
      stream: true,
      tools,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userMessage },
      ],
    })
    // モデルがツールを呼んだとき（引数つき）
    .on("functionToolCall", (call) =>
      console.log(`\n  [ツール呼び出し] ${call.name}(${call.arguments})`)
    )
    // ツール関数の戻り値
    .on("functionToolCallResult", (result) =>
      console.log(`  [ツール結果] ${result}\n`)
    )
    // 最終回答テキストの差分（ストリーミング）
    .on("content", (delta) => process.stdout.write(delta));

  await runner.finalChatCompletion();
  console.log("\n");
}

main().catch((err) => {
  console.error("\nエラー:", err.message || err);
  process.exit(1);
});
