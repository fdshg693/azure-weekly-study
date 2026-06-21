// ============================================================================
// コントロールプレーン（管理面 / ARM）クライアント — DefaultAzureCredential + ARM REST
// ----------------------------------------------------------------------------
// PLAN.md §4 ステップ2 の主役。データプレーン（openai-client.js）と対になる「もう一方の面」。
// 同じ Azure OpenAI アカウントを触るのに、データプレーンとは次の「3つの違い」がある:
//   1. 認証スコープが別 … データ面は "cognitiveservices.azure.com" だが、
//      管理面は "management.azure.com"（ARM）。同じ az login でもトークンの宛先が違う。
//   2. API バージョン体系が別 … 推論用(2025-04-01-preview 等)とは無関係に、
//      ARM のリソース管理用バージョン（GA 2025-06-01）を使う。
//   3. 必要な RBAC ロールが別 … 一覧取得は Cognitive Services Contributor 相当
//      （推論用の OpenAI User しか持っていないと 403 になりうる → ステップ5 で体験）。
//
// 敢えて SDK（@azure/arm-cognitiveservices）を使わず、生の ARM REST を fetch で叩く。
// 「2つの面」の違い（宛先スコープ・API バージョン・URL 構造）をコード上で明示的に
// 見せるための学習的な選択。書き込み（作成/削除）はステップ3 で足す。
// ============================================================================

const { getBearerTokenProvider, DefaultAzureCredential } = require("@azure/identity");

// 操作対象アカウントの「フルリソース ID」だけが環境固有値。ここから subscription /
// resourceGroup / account 名を取り出す（terraform output openai_account_id と同じ値）。
// 例: /subscriptions/xxxx/resourceGroups/rg-aigw-dev-seiwan/providers/Microsoft.CognitiveServices/accounts/aoai-aigw-dev-seiwan
const accountId = process.env.AZURE_OPENAI_ACCOUNT_ID;

// ARM リソース管理用の API バージョン。推論用バージョン（§勘所2）とは別系統。
// 秘密ではない「アプリ設定」なのでここに集約（env で上書き可能）。
const ARM_API_VERSION = process.env.AZURE_OPENAI_ARM_API_VERSION || "2025-06-01";

const ARM_BASE = "https://management.azure.com";

// DefaultAzureCredential はローカルでは `az login`、Azure 上ではマネージド ID を使う。
// データプレーンと違い、宛先は ARM（management.azure.com）。このスコープ差が最重要。
const credential = new DefaultAzureCredential();
const armTokenProvider = getBearerTokenProvider(credential, "https://management.azure.com/.default");

// フルリソース ID から subscription / resourceGroup / account 名を取り出す。
function parseAccountId(id) {
  const m =
    /^\/subscriptions\/([^/]+)\/resourceGroups\/([^/]+)\/providers\/Microsoft\.CognitiveServices\/accounts\/([^/]+)$/i.exec(
      id || ""
    );
  if (!m) {
    throw new Error(
      "AZURE_OPENAI_ACCOUNT_ID が未設定または不正です（app/.env を確認、または `just app-env-sync`）"
    );
  }
  return { subscriptionId: m[1], resourceGroup: m[2], accountName: m[3] };
}

// アカウント配下の相対パス（例 "/deployments"）を ARM へ叩く共通ヘルパ。
// method / body を受け取り、読み取り(GET)も書き込み(PUT/DELETE)も同じ経路で扱う。
async function armRequest(method, relativePath, body) {
  const { subscriptionId, resourceGroup, accountName } = parseAccountId(accountId);
  const accountPath =
    `/subscriptions/${subscriptionId}/resourceGroups/${resourceGroup}` +
    `/providers/Microsoft.CognitiveServices/accounts/${accountName}`;
  const url = `${ARM_BASE}${accountPath}${relativePath}?api-version=${ARM_API_VERSION}`;

  // ARM スコープのトークンを取得（プロバイダがキャッシュ・更新を面倒みる）。Node 20+ の global fetch を使う。
  const token = await armTokenProvider();
  const headers = { Authorization: `Bearer ${token}` };
  const init = { method, headers };
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
    init.body = JSON.stringify(body);
  }

  const resp = await fetch(url, init);

  if (!resp.ok) {
    // 403(ロール不足) / 404 / 409 / 429(クォータ超過) などをそのまま呼び出し側へ伝える
    // （ステップ5 の「叩いて変化を体験」に効く）。
    const text = await resp.text();
    const err = new Error(`ARM ${resp.status}: ${text}`);
    err.status = resp.status;
    throw err;
  }
  // DELETE は本文が空（202/204）のことがある。空なら null を返す。
  const text = await resp.text();
  return text ? JSON.parse(text) : null;
}

// 読み取り専用の薄いラッパ（呼び出し側の意図を明示するため）。
const armGet = (relativePath) => armRequest("GET", relativePath);

// ARM のデプロイ表現を UI で使いやすい形に整形（一覧・作成で共通利用）。
// 重要: "デプロイ名"(name) と "モデル名"(properties.model.name) は別物（PLAN §6）。
function shapeDeployment(d) {
  return {
    deployment: d.name,
    model: d.properties?.model?.name,
    version: d.properties?.model?.version,
    state: d.properties?.provisioningState,
    sku: d.sku?.name,
    capacity: d.sku?.capacity,
  };
}

// このアカウントに作成済みのモデルデプロイ一覧（`az cognitiveservices account deployment list` 相当）。
async function listDeployments() {
  const body = await armGet("/deployments");
  return (body.value || []).map(shapeDeployment);
}

// このアカウント（= リージョン）でデプロイ可能なベースモデル一覧
// （`az cognitiveservices account list-models` 相当）。UI のモデル選択肢の材料になる。
async function listModels() {
  const body = await armGet("/models");
  return (body.value || []).map((m) => ({
    model: m.name,
    version: m.version,
    format: m.format,
    // SKU（Standard / GlobalStandard 等）はデプロイ作成時の選択肢になる（ステップ3 で使う）。
    skus: (m.skus || []).map((s) => s.name),
    maxCapacity: m.maxCapacity,
  }));
}

// モデルデプロイの作成（または更新）。`az cognitiveservices account deployment create` 相当。
// PUT は冪等で、同じデプロイ名なら設定更新になる。
//   入力: { deployment, model, version, format?, sku?, capacity? }
//   - deployment : 推論時に指定する任意の名前（モデル名と別でもよい）
//   - model/version/format : デプロイするベースモデル（`listModels()` の候補から選ぶ）
//   - sku/capacity : SKU と容量(TPM)。容量がクォータ超過だと ARM が 4xx を返す。
// 注意: 作成は長時間処理(LRO)。戻り値の state は "Accepted"/"Creating" のこともあり、
//       "Succeeded" になるまで UI 側は `listDeployments()` でポーリングする想定。
async function createDeployment({ deployment, model, version, format = "OpenAI", sku = "GlobalStandard", capacity = 10 }) {
  const body = {
    sku: { name: sku, capacity },
    properties: { model: { format, name: model, version } },
  };
  const created = await armRequest("PUT", `/deployments/${encodeURIComponent(deployment)}`, body);
  return shapeDeployment(created);
}

// モデルデプロイの削除。`az cognitiveservices account deployment delete` 相当。
// こちらも LRO（202 で受理→バックグラウンド削除）。本文が空なら null が返る。
async function deleteDeployment(deployment) {
  await armRequest("DELETE", `/deployments/${encodeURIComponent(deployment)}`);
  return { deployment, deleted: true };
}

module.exports = { listDeployments, listModels, createDeployment, deleteDeployment, ARM_API_VERSION };
