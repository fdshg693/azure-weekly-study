# restartPolicy の因果を確かめる: わざと終了するコンテナを立て、再起動の有無を観察する。
#   組合せの見どころ:
#     -Policy OnFailure -ExitCode 1  → 異常終了なので再起動し restartCount が増える
#     -Policy OnFailure -ExitCode 0  → 正常終了なので再起動しない (1 回で Terminated)
#     -Policy Always    -ExitCode 0  → 正常終了でも毎回再起動する
#     -Policy Never     -ExitCode 1  → 失敗しても再起動しない
param(
    [Parameter(Mandatory)]
    [ValidateSet('Always', 'OnFailure', 'Never')]
    [string]$Policy,
    [int]$ExitCode = 1,
    [int]$WaitSec = 40    # 数回の終了→再起動が回るのを待ってから観察する
)

. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$reg = Get-RegistryOutputs
$image = "$($cfg.Repository):$($cfg.Tag)"
$cgName = "cg-$($cfg.Prefix)-restart"

Write-Host "== restart 実験: policy=$Policy exitCode=$ExitCode ==" -ForegroundColor Cyan
# 前回の状態を引きずらないよう作り直す (既存があれば消す)。
az container delete --resource-group $cfg.ResourceGroup --name $cgName --yes 2>$null | Out-Null

az deployment group create `
    --resource-group $cfg.ResourceGroup `
    --name restart `
    --template-file (Join-Path $PSScriptRoot '..\restart.bicep') `
    --parameters `
        prefix=$($cfg.Prefix) `
        acrLoginServer=$($reg.AcrLoginServer) `
        uamiResourceId=$($reg.UamiResourceId) `
        image=$image `
        restartPolicy=$Policy `
        exitCode=$ExitCode | Out-Null

Write-Host "再起動が回るのを待機 ($WaitSec 秒)..." -ForegroundColor DarkGray
Start-Sleep -Seconds $WaitSec

Write-Host "`n== 結果 (restartCount と現在の状態に注目) ==" -ForegroundColor Cyan
az container show --resource-group $cfg.ResourceGroup --name $cgName `
    --query "{policy:restartPolicy, restartCount:containers[0].instanceView.restartCount, current:containers[0].instanceView.currentState.state, exitCode:containers[0].instanceView.currentState.exitCode}" `
    -o jsonc

Write-Host "`nヒント: 別の組合せでもう一度叩くと挙動の差が分かります。確認後は task delete CG=$cgName で破棄を。" -ForegroundColor Yellow
