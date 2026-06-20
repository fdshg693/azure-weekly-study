# simple で作った既存 AKS に対し、Workload Identity を「その場で有効化」する。
#   --enable-oidc-issuer       : クラスタが OIDC issuer (トークンの発行元) を公開する
#   --enable-workload-identity : SA トークン → Managed Identity への交換 webhook を入れる
# どちらも冪等。simple のクラスタ定義 (Bicep) はあえて触らず、ここで in-place 更新する
# (既存リソースの一部機能だけを後付けする例として)。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$aks = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).AksName

Write-Host "AKS '$aks' に OIDC issuer + Workload Identity を有効化します (数分かかります)..."
az aks update `
    --resource-group $ResourceGroup `
    --name $aks `
    --enable-oidc-issuer `
    --enable-workload-identity

# 確認: OIDC issuer URL を表示する (この後 just deploy が FIC の issuer に使う)。
$issuer = az aks show --resource-group $ResourceGroup --name $aks --query "oidcIssuerProfile.issuerUrl" -o tsv
Write-Host "OIDC issuer URL: $issuer"
