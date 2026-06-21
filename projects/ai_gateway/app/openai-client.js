// ============================================================================
// データプレーン（推論面）クライアント — AzureOpenAI + Managed Identity
// ----------------------------------------------------------------------------
// PLAN.md §4 ステップ1 の主役。ここで押さえる勘所は 2 つ:
//   1. 「デプロイ名」で呼ぶ … AzureOpenAI クライアントは deployment 名を固定して作る。
//      OpenAI 本家は「モデル名」で呼ぶが、Azure OpenAI は推論時に必ず "デプロイ名" を指定する。
//   2. 認証は Managed Identity … API キーではなく DefaultAzureCredential 由来の
//      Entra ID トークンで認証する（IaC 側で local_auth_enabled=false / キーレス強制）。
//
// AzureOpenAI クライアントは deployment / apiVersion をコンストラクタで固定するため、
// デプロイ名ごとに 1 つ生成してキャッシュする（リクエスト毎の生成を避ける）。
// ============================================================================

const { AzureOpenAI } = require("openai");
const { getBearerTokenProvider, DefaultAzureCredential } = require("@azure/identity");

// エンドポイントだけが環境固有値なので env から取得する。
// 例: https://aoai-aigw-dev-seiwan.openai.azure.com/（`just env-sync` で .env に書き出せる）
const endpoint = process.env.AZURE_OPENAI_ENDPOINT;

// データプレーン推論用の API バージョン。Responses API（responses.create）に対応した値を使う。
// 秘密ではない「アプリ設定」なので env ではなくここに集約する（chatbot プロジェクト踏襲）。
const API_VERSION = process.env.AZURE_OPENAI_API_VERSION || "2025-04-01-preview";

// DefaultAzureCredential はローカルでは `az login` の資格情報、
// Azure 上（App Service 等）ではマネージド ID を自動で使う。キー不要。
const credential = new DefaultAzureCredential();
const scope = "https://cognitiveservices.azure.com/.default";
const azureADTokenProvider = getBearerTokenProvider(credential, scope);

// デプロイ名 -> AzureOpenAI クライアントのキャッシュ。
const clientsByDeployment = new Map();

// 指定したデプロイ名に紐づくクライアントを取得（無ければ生成してキャッシュ）。
function getClient(deployment) {
  if (!endpoint) {
    throw new Error("AZURE_OPENAI_ENDPOINT が未設定です（app/.env を確認、または `just env-sync`）");
  }
  if (!deployment) {
    throw new Error("デプロイ名が指定されていません（AZURE_OPENAI_DEPLOYMENT か リクエストの deployment）");
  }
  if (!clientsByDeployment.has(deployment)) {
    clientsByDeployment.set(
      deployment,
      new AzureOpenAI({ endpoint, azureADTokenProvider, deployment, apiVersion: API_VERSION })
    );
  }
  return clientsByDeployment.get(deployment);
}

module.exports = { getClient, API_VERSION };
