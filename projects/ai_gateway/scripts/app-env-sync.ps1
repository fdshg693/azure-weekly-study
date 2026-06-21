# ============================================================================
# app/.env 生成（terraform output → アプリ設定）— justfile の `just app-env-sync` から呼ばれる
# ============================================================================
# アプリが使う 2 つの「面」の宛先を terraform output から書き出す:
#   - AZURE_OPENAI_ENDPOINT   : データプレーン推論の宛先（*.openai.azure.com）
#   - AZURE_OPENAI_ACCOUNT_ID : コントロールプレーン(ARM)の宛先（フルリソース ID）
#   - AZURE_OPENAI_DEPLOYMENT : 既定デプロイ名（環境変数 AOAI_DEPLOYMENT で上書き可・既定 gpt-4.1）
# 巨大ワンライナーを justfile に埋め込まないためスクリプトに切り出している。

param(
  [string] $OutFile = "app/.env"
)

$ErrorActionPreference = "Stop"

# terraform output から環境固有値を取得（-raw で素の文字列を得る）。
$endpoint  = terraform output -raw openai_endpoint
$accountId = terraform output -raw openai_account_id

# 既定デプロイ名は環境変数 AOAI_DEPLOYMENT を優先し、未設定なら gpt-4.1。
$deployment = $env:AOAI_DEPLOYMENT
if (-not $deployment) { $deployment = "gpt-4.1" }

# app/.env を書き出す（既存値があれば上書き。.env は .gitignore 済み）。
$lines = @(
  "AZURE_OPENAI_ENDPOINT=$endpoint",
  "AZURE_OPENAI_ACCOUNT_ID=$accountId",
  "AZURE_OPENAI_DEPLOYMENT=$deployment"
)
Set-Content -Path $OutFile -Value $lines

Write-Host "Wrote $OutFile" -ForegroundColor Green
Write-Host "  endpoint   : $endpoint"
Write-Host "  account-id : (set)"
Write-Host "  deployment : $deployment"
