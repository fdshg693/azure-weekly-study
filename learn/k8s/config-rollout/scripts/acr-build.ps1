# api/ と front/ のイメージを simple の ACR にビルド & プッシュする。
# この章のキモ: 1 つのソースから ARG を変えて v1 / v2 / v2-bad を作り分ける。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$acr = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).AcrName

# 通常版 v1
az acr build --registry $acr --image config/api:v1 --build-arg APP_VERSION=v1 ./api
# 新版 v2 (応答に new_in_v2 が増える)
az acr build --registry $acr --image config/api:v2 --build-arg APP_VERSION=v2 ./api
# 壊れた v2: /healthz が 500 を返し readiness が通らない (ロールアウト停止の実験用)
az acr build --registry $acr --image config/api:v2-bad --build-arg APP_VERSION=v2-bad --build-arg BREAK_HEALTH=true ./api
# フロントは 1 種類のみ
az acr build --registry $acr --image config/front:v1 ./front
