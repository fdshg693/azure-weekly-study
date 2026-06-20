# （任意・ローカル Docker が要る経路）az acr login → docker build → docker push。
# az acr build との対比用: こちらは「手元でビルドして push」、build.ps1 は「クラウドでビルド」。
# az acr login は admin user ではなく Entra のトークン認証で行う＝キーレス。
param(
    [string]$Tag = 'v1',
    [string]$Version = ''
)

. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$acr = Get-AcrName -ResourceGroup $cfg.ResourceGroup
$loginServer = Get-Output -ResourceGroup $cfg.ResourceGroup -Name 'acrLoginServer'
$repo = $cfg.Repository
if (-not $Version) { $Version = $Tag }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker が見つかりません。ローカル Docker が無い場合は `task build`（az acr build）を使ってください。"
}

$appPath = Join-Path $PSScriptRoot '..\app'
$image = "$loginServer/${repo}:$Tag"

Write-Host "az acr login（トークン認証＝キーレス、admin user 不使用）: $acr" -ForegroundColor Cyan
az acr login --name $acr

Write-Host "docker build → push: $image" -ForegroundColor Cyan
docker build --build-arg "VERSION=$Version" -t $image $appPath
docker push $image
