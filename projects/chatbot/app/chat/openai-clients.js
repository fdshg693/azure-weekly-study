// ============================================================================
// Azure OpenAI クライアントの生成・キャッシュ
// ----------------------------------------------------------------------------
// AzureOpenAI クライアントは deployment / apiVersion をコンストラクタで固定するため、
// 選択できるモデルごとに 1 つずつ用意してキャッシュしておく（リクエスト毎の生成を避ける）。
// 認証は DefaultAzureCredential 由来の Entra ID トークンを使う（API キー不要）。
// ============================================================================

const { AzureOpenAI } = require("openai");
const { getBearerTokenProvider, DefaultAzureCredential } = require("@azure/identity");
const { CHAT_MODELS } = require("../config/models");

// エンドポイントだけが環境固有値なので env から取得する。
const endpoint = process.env.AZURE_OPENAI_ENDPOINT;

// DefaultAzureCredential はローカル開発時は `az login` の資格情報、
// App Service 上ではシステム割り当てマネージド ID を自動で使用する。
const credential = new DefaultAzureCredential();
const scope = "https://cognitiveservices.azure.com/.default";
const azureADTokenProvider = getBearerTokenProvider(credential, scope);

// id -> AzureOpenAI クライアントのマップ。モデルごとに 1 つだけ生成して使い回す。
const clientsByModelId = new Map(
  CHAT_MODELS.map((model) => [
    model.id,
    new AzureOpenAI({
      endpoint,
      azureADTokenProvider,
      deployment: model.deployment,
      apiVersion: model.apiVersion,
    }),
  ])
);

// モデル id からキャッシュ済みクライアントを取得する。
function getClient(modelId) {
  return clientsByModelId.get(modelId);
}

module.exports = { getClient };
