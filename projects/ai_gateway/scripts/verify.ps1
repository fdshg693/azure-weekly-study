# ============================================================================
# ステップ0 動作確認スクリプト
# ============================================================================
# justfile の `just verify` から呼ばれる。土台（Azure OpenAI アカウント本体 +
# ロール割り当て）が出来ているかを確認する読み取り専用スクリプト。
#   1. アカウントのプロビジョニング状態
#   2. モデルデプロイ一覧（この時点では「空」が正解 = 後続ステップで作る対象）
#   3. 自分に割り当てられたロール（OpenAI User / Contributor の2つが見えるはず）
# 巨大ワンライナーを justfile に埋め込まないため、スクリプトに切り出している。

param(
  [Parameter(Mandatory)] [string] $ResourceGroup,
  [Parameter(Mandatory)] [string] $OpenAiAccount
)

$ErrorActionPreference = "Stop"

Write-Host "=== 1. Azure OpenAI アカウント ===" -ForegroundColor Cyan
az cognitiveservices account show -n $OpenAiAccount -g $ResourceGroup --output table

Write-Host "`n=== 2. モデルデプロイ一覧（この時点では空が正解） ===" -ForegroundColor Cyan
az cognitiveservices account deployment list -n $OpenAiAccount -g $ResourceGroup --output table

Write-Host "`n=== 3. ロール割り当て ===" -ForegroundColor Cyan
# スコープはハードコードせず terraform output から取得する（環境差を吸収）。
$accountId = (terraform output -raw openai_account_id)
az role assignment list --scope $accountId --output table
