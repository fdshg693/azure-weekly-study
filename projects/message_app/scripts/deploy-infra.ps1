# Azure へインフラ（Cosmos / Redis / App Service x2 / Functions）を Bicep でデプロイする。
# ※ 実リソースを作成する。README のガードレールに従い、明示的な実行時のみ使う。
param(
  [string]$ResourceGroup = "rg-msgapp-dev",
  [string]$Location = "japaneast",
  [string]$Prefix = "msgapp"
)
$ErrorActionPreference = 'Stop'
$infra = Join-Path (Split-Path $PSScriptRoot -Parent) 'infra'

Write-Host "リソースグループを作成/確認: $ResourceGroup ($Location)" -ForegroundColor Cyan
az group create -n $ResourceGroup -l $Location --output none

Write-Host "Bicep をデプロイ中（数分かかります。Redis 作成が特に長い）..." -ForegroundColor Cyan
az deployment group create `
  -g $ResourceGroup `
  -n main `
  --template-file (Join-Path $infra 'main.bicep') `
  --parameters prefix=$Prefix `
  --output table

Write-Host ""
Write-Host "完了。出力 URL は `task outputs` で確認できます。" -ForegroundColor Green
Write-Host "次: `task publish` でアプリのコードを配置してください。" -ForegroundColor Cyan
