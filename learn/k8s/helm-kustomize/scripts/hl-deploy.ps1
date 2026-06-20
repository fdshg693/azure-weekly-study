# Helm chart を指定環境にデプロイ (upgrade --install = 無ければ install / あれば upgrade)。
#
# ACR は文字列置換ではなく `--set image.registry=<ACR>` で実行時に注入する
# (= Kustomize の images transformer に対応する Helm 側のやり方)。リリース名は
# 環境ごとに app-dev / app-prod とし、別 namespace (hk-dev / hk-prod) に入れる。
param(
    [ValidateSet('dev', 'prod')][string]$Env = 'dev',
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$acr = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).AcrLoginServer
$ns = "hk-$Env"

helm upgrade --install "app-$Env" helm/app `
    --namespace $ns --create-namespace `
    --values helm/app/values-$Env.yaml `
    --set image.registry=$acr
