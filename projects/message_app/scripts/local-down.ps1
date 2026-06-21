# ローカル依存を停止・削除する（学習後の後片付け）。
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

Push-Location $root
try {
  docker compose down
} finally {
  Pop-Location
}
Write-Host "ローカル依存を停止しました。" -ForegroundColor Green
