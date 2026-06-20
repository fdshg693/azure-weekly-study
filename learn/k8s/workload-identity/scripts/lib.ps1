# 共通ヘルパ。各スクリプトが dot-source して使う。
# - simple のデプロイ出力 (ACR / AKS / PostgreSQL) を取得する。
# - このプロジェクトの UAMI 情報 (clientId / principalId) を取得する。

# このプロジェクト共通の固定値 (manifests / Bicep の既定値と一致させること)。
$script:WiUamiName  = 'id-aks-pg-workload'
$script:WiNamespace = 'workload-identity'
$script:WiSaName    = 'pg-accessor'

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
        PgFqdn         = $d.properties.outputs.pgFqdn.value
        PgAdminUser    = $d.properties.outputs.pgAdminUser.value
        PgName         = $d.properties.outputs.pgFqdn.value.Split('.')[0]  # FQDN の先頭ラベル = サーバー名
    }
}

# UAMI (just deploy で作成済み前提) の clientId / principalId を返す。
function Get-Uami {
    param(
        [string]$ResourceGroup = 'rg-aks-demo',
        [string]$UamiName = $script:WiUamiName
    )
    $u = az identity show --resource-group $ResourceGroup --name $UamiName | ConvertFrom-Json
    if (-not $u) {
        throw "Managed Identity '$UamiName' が '$ResourceGroup' に見つかりません。先に `just deploy` を実行してください。"
    }
    [pscustomobject]@{
        Name        = $u.name
        ClientId    = $u.clientId
        PrincipalId = $u.principalId
    }
}
