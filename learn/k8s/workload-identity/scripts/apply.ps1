# マニフェストを workload-identity 名前空間に適用する。
# 環境依存の 4 つのプレースホルダを Bicep 出力・simple のデプロイ出力で置換してから流す:
#   __ACR_LOGIN_SERVER__ : イメージのレジストリ
#   __PG_FQDN__          : 接続先 PostgreSQL の FQDN
#   __PG_USER__          : DB ログイン名 (= UAMI 名)
#   __UAMI_CLIENT_ID__   : SA 注釈に入れる Managed Identity の clientId
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$o = Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName
$u = Get-Uami -ResourceGroup $ResourceGroup

kubectl apply -f manifests/namespace.yaml

# ServiceAccount: client-id を置換 (どの Managed Identity になりすますか)。
(Get-Content manifests/serviceaccount.yaml -Raw) `
    -replace '__UAMI_CLIENT_ID__', $u.ClientId | kubectl apply -f -

# API Deployment: ACR / PG FQDN / PG ユーザー (= UAMI 名) を置換。
(Get-Content manifests/api-deployment.yaml -Raw) `
    -replace '__ACR_LOGIN_SERVER__', $o.AcrLoginServer `
    -replace '__PG_FQDN__', $o.PgFqdn `
    -replace '__PG_USER__', $u.Name | kubectl apply -f -

(Get-Content manifests/front-deployment.yaml -Raw) `
    -replace '__ACR_LOGIN_SERVER__', $o.AcrLoginServer | kubectl apply -f -

kubectl apply -f manifests/services.yaml
kubectl apply -f manifests/ingress.yaml
