# ============================================================================
# 推論エンドポイント叩き（ステップ1 動作確認）— justfile の `just infer` から呼ばれる
# ============================================================================
# 起動中のアプリ（POST /infer）へプロンプトを 1 発投げて応答を表示する。
# Deployment を渡すと、その都度デプロイ名を上書きできる（省略時はアプリの既定）。
# 巨大ワンライナーを justfile に埋め込まないため、スクリプトに切り出している。

param(
  [Parameter(Mandatory)] [string] $Prompt,
  [string] $Deployment = "",
  [string] $BaseUrl = "http://localhost:3000"
)

$ErrorActionPreference = "Stop"

# Deployment が空ならフィールド自体を送らず、アプリ側の既定（AZURE_OPENAI_DEPLOYMENT）に委ねる。
$payload = @{ prompt = $Prompt }
if ($Deployment -ne "") { $payload.deployment = $Deployment }
$body = $payload | ConvertTo-Json -Compress

Write-Host "POST $BaseUrl/infer" -ForegroundColor Cyan
Write-Host "  prompt     : $Prompt"
Write-Host "  deployment : $(if ($Deployment -ne '') { $Deployment } else { '(アプリ既定)' })"

try {
  $res = Invoke-RestMethod -Uri "$BaseUrl/infer" -Method Post -ContentType "application/json" -Body $body
  Write-Host "`n=== 応答 (deployment=$($res.deployment)) ===" -ForegroundColor Green
  Write-Host $res.reply
}
catch {
  # 401/403（権限）/ 404（デプロイ名違い）/ 429（容量超過）などをそのまま観測できるようにする。
  Write-Host "`n=== エラー ===" -ForegroundColor Red
  if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message } else { Write-Host $_.Exception.Message }
  exit 1
}
