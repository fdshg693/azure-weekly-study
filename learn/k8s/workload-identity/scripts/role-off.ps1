# 【因果実験: 外す側】
# UAMI を PostgreSQL の Entra 管理者から外す。
# トークンは取れても DB がログインを拒否 → /api の db.connected が false に変わる。
# auth トピックで学んだ「ロールで挙動が変わる」を k8s + DB で再現する観察点。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$pg = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).PgName
$u  = Get-Uami -ResourceGroup $ResourceGroup

Write-Host "PostgreSQL '$pg' の Entra 管理者から '$($u.Name)' を外します..."
az postgres flexible-server ad-admin delete `
    --resource-group $ResourceGroup `
    --server-name $pg `
    --object-id $u.PrincipalId `
    --yes

Write-Host "完了。/api の db.connected が false に変わるはず。`just role-on` で戻せる。"
