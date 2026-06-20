# az acr build（ACR Tasks）でクラウド側ビルド & push する。ローカル Docker 不要。
# 主役の体験: 「Dockerfile を送るとレジストリ側でビルドされ、結果がそのまま push される」。
param(
    [string]$Tag = 'v1',           # イメージタグ（<repo>:<Tag>）
    [string]$Version = ''          # ページに焼くバージョン文字列（既定は Tag と同じ）
)

. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$acr = Get-AcrName -ResourceGroup $cfg.ResourceGroup
$repo = $cfg.Repository
if (-not $Version) { $Version = $Tag }

$appPath = Join-Path $PSScriptRoot '..\app'

Write-Host "ACR Tasks でビルド中: $acr / ${repo}:$Tag (VERSION=$Version)" -ForegroundColor Cyan
# --build-arg で中身を変えられる＝同じタグで違う digest を作れる（digest 実験で利用）。
az acr build --registry $acr --image "${repo}:$Tag" --build-arg "VERSION=$Version" $appPath
