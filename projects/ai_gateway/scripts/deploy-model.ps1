# ============================================================================
# モデルデプロイ作成（コントロールプレーン書き込み）— justfile の `just deploy-model` から呼ばれる
# ============================================================================
# ステップ1 の前提「手動で 1 つだけモデルをデプロイ」を簡単に行うための薄いラッパー。
# 本来このデプロイ操作は PLAN.md のステップ3 で「管理 UI から」行う対象だが、
# それまでの動作確認用に CLI からも叩けるようにしておく（後でアプリ実装に置き換わる）。
#
# 既定は Responses API 対応の GPT-4.1 / GlobalStandard。容量(TPM)は学習用に小さめ。
# モデル名/バージョン/SKU の可用性は `just models` で確認して調整すること。
# 巨大ワンライナーを justfile に埋め込まないため、スクリプトに切り出している。

param(
  [Parameter(Mandatory)] [string] $ResourceGroup,
  [Parameter(Mandatory)] [string] $OpenAiAccount,
  # デプロイ名（推論時に指定する名前）。既定はモデル名と一致させる（規約）。
  [string] $DeploymentName = "gpt-4.1",
  [string] $ModelName      = "gpt-4.1",
  [string] $ModelVersion   = "2025-04-14",
  [string] $ModelFormat    = "OpenAI",
  [string] $Sku            = "GlobalStandard",
  [int]    $Capacity       = 10
)

$ErrorActionPreference = "Stop"

Write-Host "=== モデルデプロイを作成 ===" -ForegroundColor Cyan
Write-Host "  account     : $OpenAiAccount ($ResourceGroup)"
Write-Host "  deployment  : $DeploymentName  (model: $ModelName $ModelVersion)"
Write-Host "  sku         : $Sku  capacity(TPM): $Capacity"

# デプロイ作成（既存なら更新）。容量超過やリージョン非対応は az 側がエラーで知らせる。
az cognitiveservices account deployment create `
  -n $OpenAiAccount -g $ResourceGroup `
  --deployment-name $DeploymentName `
  --model-name $ModelName --model-version $ModelVersion --model-format $ModelFormat `
  --sku-name $Sku --sku-capacity $Capacity `
  --output table

Write-Host "`n完了。`just deploy-list` で一覧、`just infer ""...""` で推論を試せる。" -ForegroundColor Green
