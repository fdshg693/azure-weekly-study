// ============================================================================
// Responses API × ツール（function calling）デモ CLI（gpt-5 想定）
// ----------------------------------------------------------------------------
// なぜこのスクリプトを作るか:
//   server.js は `openai.responses.create`（= Responses API）を使うが、
//   gpt-4o-mini のデプロイ（Japan East / GlobalStandard）では Responses API の
//   パスが提供されず 404「Resource not found」になっていた。
//   一方 tools-demo.js は Chat Completions API を使うため成功していた。
//   → 本スクリプトは「Responses API に対応したモデル（gpt-5）に対して
//      Responses API が実際に通るか」を最小構成で確認するためのもの。
//
// 参考: openai-node/examples/responses/streaming-tools.ts, stream.ts
//
// 実行: node responses-demo.js "あなたの聞きたいこと"
//   例) node responses-demo.js "私の名前と契約プラン、今月の請求額を教えて。"
//
// 設定の出どころ:
//   AZURE_OPENAI_ENDPOINT … app/.env（環境固有値）。例: https://aoai-chatbot-dev-xxx.openai.azure.com/
//   モデル名 / api-version / 推論強度 … config/models.js（コミット対象のアプリ設定）
//   --deployment <名前> … 別デプロイで試したいときの一時上書き（実験用 CLI フラグ）
// ============================================================================

// tools-demo.js と同様、ローカル開発では app/.env から環境変数を読み込む。
require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });

const { AzureOpenAI } = require("openai");
const { getBearerTokenProvider, DefaultAzureCredential } = require("@azure/identity");
const { MODELS } = require("../config/models");

const endpoint = process.env.AZURE_OPENAI_ENDPOINT;
// モデル設定は config/models.js（推論モデル）から取得する。
// ただし本スクリプトは「別デプロイで Responses API が通るか」を試す実験用なので、
// その場限りの上書きとして CLI の --deployment だけ残す（既定は config の値）。
const deployment = getFlag("--deployment") || MODELS.reasoning.deployment;
const apiVersion = MODELS.reasoning.apiVersion;
const reasoningEffort = MODELS.reasoning.reasoningEffort;

// DefaultAzureCredential はローカルでは `az login`、App Service 上では
// マネージド ID を自動利用する（server.js と同じ認証パターン）。
const credential = new DefaultAzureCredential();
const scope = "https://cognitiveservices.azure.com/.default";
const azureADTokenProvider = getBearerTokenProvider(credential, scope);

const openai = new AzureOpenAI({ endpoint, azureADTokenProvider, deployment, apiVersion });

// ----------------------------------------------------------------------------
// モックの「ユーザーデータベース」（tools-demo.js と同じもの）。
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
const CURRENT_USER_ID = "user-001";

// ツールの実体。Responses API ではこちらで明示的に呼び出す（自動ループはしない）。
function getUserProfile({ user_id, fields }) {
  const id = user_id || CURRENT_USER_ID;
  const user = MOCK_USERS[id];
  if (!user) return { error: `ユーザー ${id} は見つかりませんでした` };
  if (Array.isArray(fields) && fields.length > 0) {
    const picked = {};
    for (const f of fields) if (f in user) picked[f] = user[f];
    return { id: user.id, ...picked };
  }
  return user;
}

// ----------------------------------------------------------------------------
// Responses API のツール定義。
// 重要: Chat Completions と形が違う。Chat では { type:"function", function:{...} }
// と入れ子だが、Responses では name/description/parameters を「フラットに」置く。
// ----------------------------------------------------------------------------
const tools = [
  {
    type: "function",
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
  },
];

const SYSTEM_PROMPT =
  "あなたは親切で簡潔に答える日本語アシスタントです。" +
  "ユーザー自身の情報（名前・プラン・請求など）を聞かれたら get_user_profile ツールを使って正確に答えてください。";

// ツール呼び出し → 結果を返して再生成、のループ上限（暴走防止）。
const MAX_TOOL_ROUNDS = 5;

async function main() {
  const userMessage =
    process.argv.slice(2).filter((a) => !a.startsWith("--")).join(" ").trim() ||
    "私の名前と契約プラン、今月の請求額を教えて。";

  console.log(`\n[設定] endpoint=${endpoint}`);
  console.log(`[設定] deployment=${deployment}  api-version=${apiVersion}`);
  console.log(`\n🧑 ユーザー: ${userMessage}\n`);

  // Responses API の input 配列。server.js と同じ積み方。
  const input = [
    { role: "system", content: SYSTEM_PROMPT },
    { role: "user", content: userMessage },
  ];

  let response = await openai.responses.create({
    model: deployment,
    input,
    tools,
    // gpt-5 は推論モデル。推論の強さは config/models.js で管理（チャット用途は軽め）。
    reasoning: { effort: reasoningEffort },
  });

  // モデルがツールを呼んだら実行し、結果を返して再度生成させるループ。
  for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
    const calls = response.output.filter((o) => o.type === "function_call");
    if (calls.length === 0) break;

    // モデルの出力（function_call を含む）をそのまま会話に積み戻す。
    input.push(...response.output);

    for (const call of calls) {
      let args = {};
      try {
        args = call.arguments ? JSON.parse(call.arguments) : {};
      } catch (_) {
        args = {};
      }
      console.log(`  [ツール呼び出し] ${call.name}(${call.arguments || "{}"})`);
      const result = getUserProfile(args);
      console.log(`  [ツール結果] ${JSON.stringify(result)}\n`);
      input.push({
        type: "function_call_output",
        call_id: call.call_id,
        output: JSON.stringify(result),
      });
    }

    response = await openai.responses.create({
      model: deployment,
      input,
      tools,
      reasoning: { effort: reasoningEffort },
    });
  }

  console.log("🤖 アシスタント:");
  console.log(response.output_text || "(空の応答)");
  console.log("");
}

// 簡易な CLI フラグ取得: --key value 形式。
function getFlag(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

main().catch((err) => {
  console.error("\nエラー:", err.status ? `${err.status} ${err.message}` : err.message || err);
  if (err.status === 404) {
    console.error(
      "\nヒント: 404 は『その deployment に Responses API のパスが無い』状態です。" +
        "\n  - config/models.js の reasoning.deployment（または --deployment）が gpt-5 のデプロイ名になっているか" +
        "\n  - そのモデル/リージョンが Responses API に対応しているか を確認してください。"
    );
  }
  process.exit(1);
});
