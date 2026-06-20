# コンテナグループ (複数コンテナ同居) の最小形をデプロイする。
# web + sidecar の 2 コンテナが同じグループ＝同じ localhost を共有することを観察する。
# 確認: task logs CG=cg-aci-sidecar CONTAINER=sidecar で "[sidecar] reached web" が出る。
. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$reg = Get-RegistryOutputs
$image = "$($cfg.Repository):$($cfg.Tag)"

Write-Host "== sidecar (web + sidecar の同居) をデプロイ ==" -ForegroundColor Cyan

az deployment group create `
    --resource-group $cfg.ResourceGroup `
    --name sidecar `
    --template-file (Join-Path $PSScriptRoot '..\sidecar.bicep') `
    --parameters `
        prefix=$($cfg.Prefix) `
        acrLoginServer=$($reg.AcrLoginServer) `
        uamiResourceId=$($reg.UamiResourceId) `
        image=$image

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n完了。少し待ってから sidecar のログを確認:" -ForegroundColor Green
    Write-Host "  task logs CG=cg-$($cfg.Prefix)-sidecar CONTAINER=sidecar" -ForegroundColor Yellow
}
