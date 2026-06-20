# （任意・ローカル Docker が要る）「キーレス pull」の体感。
# admin user を使わず、自分の Entra 認証 + RBAC で pull できることを確かめる。
# あなたがデプロイ者（Owner/Contributor 等）なら pull できる。AcrPull だけの ID による
# pull は Step 2 (aci) で UAMI を使って行使する。
param([string]$Tag = 'v1')

. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$acr = Get-AcrName -ResourceGroup $cfg.ResourceGroup
$loginServer = Get-Output -ResourceGroup $cfg.ResourceGroup -Name 'acrLoginServer'
$repo = $cfg.Repository

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker が見つかりません。pull-test はローカル Docker が要ります（push-local と同様）。"
}

Write-Host "az acr login（キーレス・トークン認証）" -ForegroundColor Cyan
az acr login --name $acr

$image = "$loginServer/${repo}:$Tag"
Write-Host "docker pull $image" -ForegroundColor Cyan
docker pull $image
Write-Host "OK: admin user を使わず（共有パスワード無しで）pull できました。" -ForegroundColor Green
