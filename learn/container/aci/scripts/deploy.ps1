# main.bicep (web の Container Group) をデプロイする。
# registry (Step 1) の出力から ACR ログインサーバと消費者 UAMI を取り出し、
# 動的な値として渡す＝「同じ ACR から keyless pull」。bicepparam を使わず
# ここで全パラメータを注入しているのは、これらが Step 1 のデプロイ結果に依存するため。
param(
    [ValidateSet('Always', 'OnFailure', 'Never')]
    [string]$Policy = 'Always'   # restartPolicy を出し入れする実験用
)

. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$reg = Get-RegistryOutputs
$image = "$($cfg.Repository):$($cfg.Tag)"

Write-Host "ACI をデプロイ: $($cfg.ResourceGroup) / image=$($reg.AcrLoginServer)/$image / restartPolicy=$Policy" -ForegroundColor Cyan
Write-Host "keyless pull に使う UAMI: $($reg.UamiResourceId)" -ForegroundColor DarkGray

az deployment group create `
    --resource-group $cfg.ResourceGroup `
    --name main `
    --template-file (Join-Path $PSScriptRoot '..\main.bicep') `
    --parameters `
        prefix=$($cfg.Prefix) `
        acrLoginServer=$($reg.AcrLoginServer) `
        uamiResourceId=$($reg.UamiResourceId) `
        image=$image `
        restartPolicy=$Policy

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n完了。task outputs / task probe で到達を確認できます。" -ForegroundColor Green
}
