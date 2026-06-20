# API Deployment のイメージを指定タグに切り替える (ローリングアップデートを起動)。
# 例: -Tag v2 / -Tag v2-bad / -Tag v1
param(
    [string]$Tag = 'v2',
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main',
    [string]$Namespace = 'config-rollout'
)
. "$PSScriptRoot/lib.ps1"

$acr = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).AcrLoginServer

kubectl set image deployment/api api="$acr/config/api:$Tag" -n $Namespace
Write-Host "→ config/api:$Tag へ更新中。状態は 'just rollout-status' で確認 (v2-bad は止まる)。"
