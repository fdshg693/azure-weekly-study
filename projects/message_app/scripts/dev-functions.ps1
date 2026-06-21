# 送信処理（Azure Functions）をローカル起動する。
# Functions Core Tools は専用の仮想環境を前提にするため、functions/.venv を使う
# （CLAUDE.md の「ツール都合でプロジェクト個別 venv を作る場合がある」に該当）。
$ErrorActionPreference = 'Stop'
$fns = Join-Path (Split-Path $PSScriptRoot -Parent) 'functions'

Push-Location $fns
try {
  if (-not (Test-Path 'local.settings.json')) {
    Copy-Item 'local.settings.json.example' 'local.settings.json'
    Write-Host "local.settings.json を作成しました。" -ForegroundColor Green
  }
  if (-not (Test-Path '.venv')) {
    Write-Host "functions/.venv を作成します。" -ForegroundColor Yellow
    python -m venv .venv
  }
  & ".\.venv\Scripts\python.exe" -m pip install -q -r requirements.txt
  & ".\.venv\Scripts\Activate.ps1"

  Write-Host "Functions 起動: http://localhost:7071 (Ctrl+C で停止)" -ForegroundColor Green
  func start
} finally {
  Pop-Location
}
