# BFF（Express）をローカル起動する。フロントも同じポートで配信される。
$ErrorActionPreference = 'Stop'
$proj = Split-Path $PSScriptRoot -Parent

if (-not (Test-Path (Join-Path $proj 'bff/node_modules'))) {
  Write-Host "依存をインストール中 (express / dotenv)..." -ForegroundColor Cyan
  Push-Location (Join-Path $proj 'bff')
  try { npm install } finally { Pop-Location }
}

# CWD をプロジェクト直下にして、プロジェクトの .env を dotenv に読ませる。
Push-Location $proj
try {
  Write-Host "BFF 起動: http://localhost:3000 (Ctrl+C で停止)" -ForegroundColor Green
  node bff/server.js
} finally {
  Pop-Location
}
