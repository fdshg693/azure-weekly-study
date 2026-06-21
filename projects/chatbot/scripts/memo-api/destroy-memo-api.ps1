<#
.SYNOPSIS
  共有メモ API（chatbot-memo-api）の App Registration を削除し、memo.auto.tfvars を片付ける。

.DESCRIPTION
  App Registration を消すと関連するサービスプリンシパルと app role 割り当ても消える。
  memo.auto.tfvars も削除するので、その後 `just apply` すると Function の EasyAuth は無効化される。
#>
param(
  [string] $DisplayName = "chatbot-memo-api",
  [string] $TfvarsPath  = "memo.auto.tfvars"
)

. "$PSScriptRoot/../_common.ps1"

$app = Find-EntraApp -DisplayName $DisplayName
if ($app) {
  Write-Host "==> App Registration '$DisplayName'（appId=$($app.appId)）を削除..." -ForegroundColor Cyan
  az ad app delete --id $($app.appId) | Out-Null
  Write-Host "    削除しました"
} else {
  Write-Host "App Registration '$DisplayName' は存在しません（スキップ）。" -ForegroundColor Yellow
}

if (Test-Path $TfvarsPath) {
  Remove-Item $TfvarsPath -Force
  Write-Host "==> $TfvarsPath を削除しました（次の just apply で EasyAuth は無効化されます）"
}

Write-Host "✅ 後片付け完了" -ForegroundColor Green
