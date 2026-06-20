# api/ front/ のイメージを simple の ACR にビルド & プッシュする。
# この章では環境差分をイメージでは出さないので、各 1 種類 (hk/api:v1, hk/front:v1) だけ。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$acr = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).AcrName

az acr build --registry $acr --image hk/api:v1 --build-arg APP_VERSION=v1 ./app/api
az acr build --registry $acr --image hk/front:v1 ./app/front
