# 【因果実験: 付ける側】
# UAMI を PostgreSQL の Microsoft Entra 管理者として登録する。
# これで UAMI 名 (= PGUSER) で、Entra トークンを使った DB ログインが通るようになる。
# --type ServicePrincipal : マネージド ID / サービスプリンシパルを指す。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$pg = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).PgName
$u  = Get-Uami -ResourceGroup $ResourceGroup

Write-Host "PostgreSQL '$pg' の Entra 管理者に '$($u.Name)' を追加します..."
az postgres flexible-server ad-admin create `
    --resource-group $ResourceGroup `
    --server-name $pg `
    --display-name $u.Name `
    --object-id $u.PrincipalId `
    --type ServicePrincipal

Write-Host "完了。/api の db.connected が true になるはず (反映に少し時間がかかることがある)。"
