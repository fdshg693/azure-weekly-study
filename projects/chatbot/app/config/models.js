// ============================================================================
// モデルレジストリ（アプリ設定。秘密情報ではないのでコミットする）
// ----------------------------------------------------------------------------
// モデル名・api-version・推論強度といった「環境によらないアプリ設定」をここに集約する。
// これらは秘密ではなく、コードと一緒にバージョン管理すべき値なので env には置かない。
// （env / App Settings に残すのは AZURE_OPENAI_ENDPOINT のような環境固有値とシークレットのみ。）
//
// なぜ env をやめたか:
//   モデルを 1 つ増やすたびに DEPLOYMENT と API_VERSION が env にペアで増殖し、
//   .env.example・Terraform・ドキュメントの 3 箇所を直す必要があってメンテ不能になる。
//   ここ 1 ファイルに集約すれば、追加は 1 エントリで済み、git 履歴で変更も追える。
//
// 命名規約（重要 / 規約A）: Azure OpenAI の「デプロイ名」は、ここの「モデル名」と一致させる。
//   例) gpt-4o-mini モデル → デプロイ名も "gpt-4o-mini"
//   Terraform 側（variables.tf / main.tf）もこの規約でデプロイするため、
//   アプリは deployment 名を env から受け取らず、この値をそのまま使える。
//   新しいモデルを足すときは、ここに 1 エントリ追加し、同じ名前でデプロイするだけ。
// ============================================================================

// 1 モデル = 1 エントリ。これが唯一の出典で、チャット画面も experiments も全部ここを参照する。
// reasoningEffort の有無が推論モデルかどうかを表す:
//   - 推論モデル（gpt-5）   → reasoningEffort を持つ。Responses API で reasoning.effort を渡す。
//   - 非推論モデル（gpt-4o-mini）→ reasoningEffort: null。reasoning を渡すとエラーになる。
// apiVersion は 2025-04-01-preview に統一している。これは Responses API（/chat が使う）に必須で、
// かつ Chat Completions（experiments/tools-demo.js）でもそのまま使えるため、モデルごとに 1 つで足りる。
const MODELS = {
  "gpt-5": {
    id: "gpt-5",
    label: "GPT-5（推論モデル・高品質）",
    deployment: "gpt-5", // = デプロイ名（規約A: モデル名と一致）
    apiVersion: "2025-04-01-preview",
    reasoningEffort: "low", // 推論の強さ: minimal / low / medium / high。チャット用途は軽めで十分
  },
  "gpt-4o-mini": {
    id: "gpt-4o-mini",
    label: "GPT-4o mini（非推論・高速）",
    deployment: "gpt-4o-mini", // = デプロイ名（規約A: モデル名と一致）
    apiVersion: "2025-04-01-preview",
    reasoningEffort: null, // 非推論モデルは reasoning を渡さない
  },
};

// ----------------------------------------------------------------------------
// チャット画面（/chat）で切り替えられるモデル一覧（MODELS から派生）
// ----------------------------------------------------------------------------
// /chat は Responses API（openai.responses.create）を使う。Responses API は推論／非推論
// どちらのモデルも呼べるため、ここに id を並べた分だけ画面のドロップダウンに出る（配列順 = 表示順）。
const CHAT_MODEL_IDS = ["gpt-5", "gpt-4o-mini"];
const CHAT_MODELS = CHAT_MODEL_IDS.map((id) => MODELS[id]);

// 画面初期表示・未指定リクエスト時に使う既定モデル。
const DEFAULT_CHAT_MODEL_ID = "gpt-5";

// id からチャット用モデル設定を引く（未知 / 選択肢外の id は既定モデルにフォールバック）。
function getChatModel(id) {
  return CHAT_MODEL_IDS.includes(id) ? MODELS[id] : MODELS[DEFAULT_CHAT_MODEL_ID];
}

module.exports = { MODELS, CHAT_MODELS, DEFAULT_CHAT_MODEL_ID, getChatModel };
