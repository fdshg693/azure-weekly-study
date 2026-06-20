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

const MODELS = {
  // Chat Completions 用（非推論モデル）。experiments/tools-demo.js が使う。
  chat: {
    deployment: "gpt-4o-mini", // = デプロイ名（規約A: モデル名と一致）
    apiVersion: "2024-10-21", // Chat Completions は旧 api-version でも動く
  },
  // Responses API 用（推論モデル）。server.js / experiments/responses-demo.js が使う。
  reasoning: {
    deployment: "gpt-5", // = デプロイ名（規約A: モデル名と一致）
    apiVersion: "2025-04-01-preview", // Responses API は新しめのプレビュー版が必須（旧版は 404）
    reasoningEffort: "low", // 推論の強さ: minimal / low / medium / high。チャット用途は軽めで十分
  },
};

module.exports = { MODELS };
