# api/ front/ のイメージを simple の ACR にビルド & プッシュする。
# このプロジェクトはイメージの作り分けは無く 1 種類ずつ (主役は ID 設定側)。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$acr = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).AcrName

az acr build --registry $acr --image wi/api:v1 ./api
az acr build --registry $acr --image wi/front:v1 ./front
