# マニフェストを config-rollout 名前空間に適用する。
# image の __ACR_LOGIN_SERVER__ を Bicep 出力 (acrLoginServer) に置換してから流す。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$acr = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).AcrLoginServer

kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/configmap.yaml

# Deployment の image だけはレジストリ名が環境依存なので、置換してから apply する。
(Get-Content manifests/api-deployment.yaml -Raw)   -replace '__ACR_LOGIN_SERVER__', $acr | kubectl apply -f -
(Get-Content manifests/front-deployment.yaml -Raw) -replace '__ACR_LOGIN_SERVER__', $acr | kubectl apply -f -

kubectl apply -f manifests/services.yaml
kubectl apply -f manifests/ingress.yaml
kubectl apply -f manifests/hpa.yaml
