# ============================================================================
# デプロイ削除（ステップ3 動作確認）— justfile の `just gw-deploy-delete` から呼ばれる
# ============================================================================
# 起動中のアプリ（DELETE /deployments/{name}）にデプロイ削除を依頼する。
# 作成→一覧反映→削除のライフサイクルを体験するための後片付け用。

param(
  [Parameter(Mandatory)] [string] $DeploymentName,
  [string] $BaseUrl = "http://localhost:3000"
)

$ErrorActionPreference = "Stop"

# デプロイ名に記号が含まれてもよいよう URL エンコードする。
$encoded = [System.Uri]::EscapeDataString($DeploymentName)

Write-Host "DELETE $BaseUrl/deployments/$DeploymentName" -ForegroundColor Cyan

try {
  $res = Invoke-RestMethod -Uri "$BaseUrl/deployments/$encoded" -Method Delete
  Write-Host "`n=== 応答 ===" -ForegroundColor Green
  $res | ConvertTo-Json -Depth 6
  Write-Host "`n`just gw-deployments` で一覧から消えたことを確認できる。"
}
catch {
  # 403（管理ロール不足）/ 404（存在しないデプロイ名）などをそのまま観測できるようにする。
  Write-Host "`n=== エラー ===" -ForegroundColor Red
  if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message } else { Write-Host $_.Exception.Message }
  exit 1
}
