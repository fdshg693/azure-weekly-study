# AKS の接続情報を取り込む。simple のデプロイ出力から aksName を引く。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$o = Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName
az aks get-credentials --resource-group $ResourceGroup --name $o.AksName --overwrite-existing
kubectl get nodes
