# main.bicep (UAMI + Federated Identity Credential) をデプロイする。
# FIC の issuer には、infra-prep で有効化した AKS の OIDC issuer URL を渡す。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main',      # simple のデプロイ名 (AKS 名の取得用)
    [string]$WiDeploymentName = 'wi'       # このプロジェクトの Bicep デプロイ名
)
. "$PSScriptRoot/lib.ps1"

$aks = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).AksName

$issuer = az aks show --resource-group $ResourceGroup --name $aks --query "oidcIssuerProfile.issuerUrl" -o tsv
if (-not $issuer) {
    throw "OIDC issuer URL が空です。先に `just infra-prep` を実行してください。"
}

az deployment group create `
    --resource-group $ResourceGroup `
    --name $WiDeploymentName `
    --template-file main.bicep `
    --parameters oidcIssuerUrl=$issuer uamiName=$script:WiUamiName namespace=$script:WiNamespace serviceAccountName=$script:WiSaName

$u = Get-Uami -ResourceGroup $ResourceGroup
Write-Host "UAMI 作成完了: name=$($u.Name) clientId=$($u.ClientId)"
