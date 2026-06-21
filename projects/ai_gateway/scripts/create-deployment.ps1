# ============================================================================
# デプロイ作成（ステップ3 動作確認）— justfile の `just gw-deploy-create` から呼ばれる
# ============================================================================
# 起動中のアプリ（POST /deployments）にデプロイ作成を依頼する。
# az CLI 直叩き（deploy-model）と違い、アプリの ARM プロキシ経由で書き込む。
# 既定は Responses API 対応の GPT-4.1 / GlobalStandard / TPM 10（deploy-model.ps1 と同じ規約）。

param(
  [string] $DeploymentName = "gpt-4.1",
  [string] $ModelName      = "gpt-4.1",
  [string] $ModelVersion   = "2025-04-14",
  [string] $ModelFormat    = "OpenAI",
  [string] $Sku            = "GlobalStandard",
  [int]    $Capacity       = 10,
  [string] $BaseUrl        = "http://localhost:3000"
)

$ErrorActionPreference = "Stop"

# アプリの POST /deployments が期待する JSON（format/sku/capacity はアプリ側に既定もある）。
$payload = @{
  deployment = $DeploymentName
  model      = $ModelName
  version    = $ModelVersion
  format     = $ModelFormat
  sku        = $Sku
  capacity   = $Capacity
}
$body = $payload | ConvertTo-Json -Compress

Write-Host "POST $BaseUrl/deployments" -ForegroundColor Cyan
Write-Host "  deployment : $DeploymentName  (model: $ModelName $ModelVersion)"
Write-Host "  sku        : $Sku  capacity(TPM): $Capacity"

try {
  $res = Invoke-RestMethod -Uri "$BaseUrl/deployments" -Method Post -ContentType "application/json" -Body $body
  Write-Host "`n=== 応答 ===" -ForegroundColor Green
  $res | ConvertTo-Json -Depth 6
  Write-Host "`n作成は時間がかかる。`just gw-deployments` で state が Succeeded になるまで確認できる。"
}
catch {
  # 403（管理ロール不足）/ 4xx（容量・クォータ超過）などをそのまま観測できるようにする。
  Write-Host "`n=== エラー ===" -ForegroundColor Red
  if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message } else { Write-Host $_.Exception.Message }
  exit 1
}
