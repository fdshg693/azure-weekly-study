# ============================================================================
# 読み取り API 叩き（ステップ2 動作確認）— justfile の `just gw-deployments` / `just gw-models` から呼ばれる
# ============================================================================
# 起動中のアプリ（コントロールプレーン読み取り: GET /deployments, /models）を叩いて
# 応答 JSON を表示する。巨大ワンライナーを justfile に埋め込まないため切り出している。

param(
  [Parameter(Mandatory)] [string] $Path,
  [string] $BaseUrl = "http://localhost:3000"
)

$ErrorActionPreference = "Stop"

Write-Host "GET $BaseUrl$Path" -ForegroundColor Cyan

try {
  $res = Invoke-RestMethod -Uri "$BaseUrl$Path" -Method Get
  Write-Host "`n=== 応答 ===" -ForegroundColor Green
  $res | ConvertTo-Json -Depth 6
}
catch {
  # 403（管理ロール不足）/ 404 などをそのまま観測できるようにする（ステップ5 の体験用）。
  Write-Host "`n=== エラー ===" -ForegroundColor Red
  if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message } else { Write-Host $_.Exception.Message }
  exit 1
}
