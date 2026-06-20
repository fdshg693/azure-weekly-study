# simple で作った既存 PostgreSQL フレキシブルサーバーに Microsoft Entra 認証を有効化する。
# パスワード認証も残したまま (Enabled) にするので、config-rollout など他プロジェクトの
# パスワード接続は壊れない。一度実行すれば足りる (冪等)。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$pg = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).PgName

Write-Host "PostgreSQL '$pg' に Entra 認証を有効化します..."
az postgres flexible-server update `
    --resource-group $ResourceGroup `
    --name $pg `
    --active-directory-auth Enabled `
    --password-auth Enabled
