# main デプロイの出力 (FQDN / IP / URL / Container Group 名) をまとめて表示する。
. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config

$d = az deployment group show --resource-group $cfg.ResourceGroup --name main | ConvertFrom-Json
$o = $d.properties.outputs
[pscustomobject]@{
    cgName = $o.cgName.value
    fqdn   = $o.fqdn.value
    ip     = $o.ip.value
    url    = $o.url.value
} | Format-List
