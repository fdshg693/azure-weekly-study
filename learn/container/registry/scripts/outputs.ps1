# デプロイ出力（ACR 名 / ログインサーバ / 消費者 UAMI）をまとめて表示する。
. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config

$d = az deployment group show --resource-group $cfg.ResourceGroup --name main | ConvertFrom-Json
$o = $d.properties.outputs
[pscustomobject]@{
    acrName        = $o.acrName.value
    acrLoginServer = $o.acrLoginServer.value
    uamiClientId   = $o.uamiClientId.value
    uamiPrincipalId = $o.uamiPrincipalId.value
    uamiResourceId = $o.uamiResourceId.value
} | Format-List
