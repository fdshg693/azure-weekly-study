# api/ のイメージを simple の ACR にビルド & プッシュする。
# 監視が主役なのでイメージは 1 種類 (observ/api:v1) だけ。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$acr = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).AcrName

az acr build --registry $acr --image observ/api:v1 --build-arg APP_VERSION=v1 ./api
