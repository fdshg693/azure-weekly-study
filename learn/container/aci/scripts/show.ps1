# Container Group の状態・再起動回数・イメージ・pull/起動イベントを覗く。
#   - restartCount      : restartPolicy 実験で増えるのを観察する数字
#   - currentState      : Running / Terminated / Waiting など
#   - events            : "Pulling"/"Pulled"/"Started" や、AcrPull が無いときの
#                         "Failed to pull image" (401/403) がここに出る (acrpull 実験で注目)
param(
    [string]$Cg = ''   # 既定は web の Container Group。restart/sidecar は名前を渡す
)

. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$name = if ($Cg) { $Cg } else { "cg-$($cfg.Prefix)-web" }

Write-Host "== $name の概要 ==" -ForegroundColor Cyan
az container show --resource-group $cfg.ResourceGroup --name $name `
    --query "{state:instanceView.state, ip:ipAddress.ip, fqdn:ipAddress.fqdn, restartPolicy:restartPolicy, restartCount:containers[0].instanceView.restartCount, current:containers[0].instanceView.currentState.state, image:containers[0].image, env:containers[0].environmentVariables}" `
    -o jsonc

Write-Host "`n== コンテナのイベント (pull / 起動 / 失敗の履歴) ==" -ForegroundColor Cyan
az container show --resource-group $cfg.ResourceGroup --name $name `
    --query "containers[0].instanceView.events[].{time:lastTimestamp, type:type, reason:name, message:message}" -o table
