# ローカル依存（Cosmos Emulator / Redis / Azurite）を docker-compose で起動する。
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

Push-Location $root
try {
  docker compose up -d
} finally {
  Pop-Location
}

Write-Host ""
Write-Host "依存を起動しました（cosmos / redis / azurite）。" -ForegroundColor Green
Write-Host "Cosmos Emulator は初回起動に 1〜2 分かかることがあります。" -ForegroundColor Yellow
Write-Host "  Data Explorer: https://localhost:8081/_explorer/index.html" -ForegroundColor Cyan
Write-Host "準備できたら別ターミナルで: task api / task functions / task bff" -ForegroundColor Cyan
