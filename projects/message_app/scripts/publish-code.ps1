# デプロイ済みインフラへ 3 つのアプリ（API / Functions / BFF）のコードを配置する。
# 前提: deploy-infra.ps1 実行済み。az login 済み。Functions Core Tools 導入済み。
param([string]$ResourceGroup = "rg-msgapp-dev")
$ErrorActionPreference = 'Stop'
$proj = Split-Path $PSScriptRoot -Parent

# デプロイ出力からアプリ名を取得
$out = az deployment group show -g $ResourceGroup -n main --query properties.outputs -o json | ConvertFrom-Json
$apiApp = $out.apiAppName.value
$bffApp = $out.bffAppName.value
$funcApp = $out.functionAppName.value
Write-Host "api=$apiApp  bff=$bffApp  func=$funcApp" -ForegroundColor DarkGray

# 一時 zip を作るヘルパ（node_modules / venv 等は含めない）
function New-Zip($srcDir, $zipPath, $exclude) {
  if (Test-Path $zipPath) { Remove-Item $zipPath }
  $items = Get-ChildItem -Path $srcDir -Force |
    Where-Object { $exclude -notcontains $_.Name }
  Compress-Archive -Path $items.FullName -DestinationPath $zipPath
}

# --- 読み取り API（Python / Oryx ビルド） ---
$apiZip = Join-Path $env:TEMP 'msgapp-api.zip'
New-Zip (Join-Path $proj 'api') $apiZip @('__pycache__', '.venv')
Write-Host "API を配置中..." -ForegroundColor Cyan
az webapp deploy -g $ResourceGroup -n $apiApp --src-path $apiZip --type zip --output none

# --- BFF（Node / Oryx ビルド） ---
$bffZip = Join-Path $env:TEMP 'msgapp-bff.zip'
New-Zip (Join-Path $proj 'bff') $bffZip @('node_modules')
Write-Host "BFF を配置中..." -ForegroundColor Cyan
az webapp deploy -g $ResourceGroup -n $bffApp --src-path $bffZip --type zip --output none

# --- Functions（Core Tools で publish） ---
Write-Host "Functions を配置中..." -ForegroundColor Cyan
Push-Location (Join-Path $proj 'functions')
try {
  func azure functionapp publish $funcApp --python
} finally {
  Pop-Location
}

Write-Host ""
Write-Host "配置完了。`task outputs` の bffUrl を開いて動作確認してください。" -ForegroundColor Green
