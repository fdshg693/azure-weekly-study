# .env と functions/local.settings.json を雛形から作る（既存があれば上書きしない）。
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

function Copy-IfMissing($src, $dst) {
  if (Test-Path $dst) {
    Write-Host "skip (既に存在): $dst" -ForegroundColor DarkGray
  } else {
    Copy-Item $src $dst
    Write-Host "作成: $dst" -ForegroundColor Green
  }
}

Copy-IfMissing "$root/.env.example" "$root/.env"
Copy-IfMissing "$root/functions/local.settings.json.example" "$root/functions/local.settings.json"
Write-Host "完了。必要なら .env を編集してください。" -ForegroundColor Cyan
