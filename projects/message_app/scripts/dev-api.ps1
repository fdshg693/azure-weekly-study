# 読み取り API（FastAPI）をローカル起動する。
# 依存はリポジトリ共有の .venv（ルート直下）へ入れる（CLAUDE.md のルール）。
param([int]$Port = 8000)
$ErrorActionPreference = 'Stop'

$proj = Split-Path $PSScriptRoot -Parent
$repo = Resolve-Path (Join-Path $proj '..' '..')
$venv = Join-Path $repo '.venv'
$py = Join-Path $venv 'Scripts/python.exe'

if (-not (Test-Path $py)) {
  Write-Host "ルート共有 .venv を作成: $venv" -ForegroundColor Yellow
  python -m venv $venv
}

& $py -m pip install -q -r (Join-Path $proj 'api/requirements.txt')

# CWD をプロジェクト直下にして、プロジェクトの .env を python-dotenv に読ませる。
Push-Location $proj
try {
  Write-Host "FastAPI 起動: http://localhost:$Port (Ctrl+C で停止)" -ForegroundColor Green
  & $py -m uvicorn main:app --app-dir api --host 0.0.0.0 --port $Port --reload
} finally {
  Pop-Location
}
