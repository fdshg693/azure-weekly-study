# 共通ヘルパ。各スクリプトが dot-source して使う。
# simple プロジェクトのデプロイ出力 (ACR / AKS) をまとめて取得する。
# このプロジェクトは DB を使わないので PG 系は読まない。

function Get-DeployOutputs {
    param(
        [string]$ResourceGroup = 'rg-aks-demo',
        [string]$DeploymentName = 'main'
    )
    $d = az deployment group show --resource-group $ResourceGroup --name $DeploymentName | ConvertFrom-Json
    if (-not $d) {
        throw "デプロイ '$DeploymentName' が '$ResourceGroup' に見つかりません。先に learn/k8s/simple をデプロイしてください。"
    }
    [pscustomobject]@{
        AcrName        = $d.properties.outputs.acrName.value
        AcrLoginServer = $d.properties.outputs.acrLoginServer.value
        AksName        = $d.properties.outputs.aksName.value
    }
}
