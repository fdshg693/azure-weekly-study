# DB 接続情報を Secret(db-conn) として config-rollout 名前空間に作る (機密の置き場)。
# PgPassword は simple の deploy 時と同じ値を渡す。接続先は simple の PostgreSQL を流用。
param(
    [string]$PgPassword,
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main',
    [string]$Namespace = 'config-rollout'
)
. "$PSScriptRoot/lib.ps1"

if (-not $PgPassword) {
    Write-Error 'PgPassword が必要です。例: just secret-create rg-aks-demo "YourPassword"'
    exit 1
}

$o = Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName

# 名前空間が無ければ作る (apply 前でも Secret を置けるように)。
kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f -

# create --dry-run | apply で「無ければ作る・あれば更新」を冪等に行う。
kubectl create secret generic db-conn -n $Namespace `
    --from-literal=PGHOST=$($o.PgFqdn) `
    --from-literal=PGUSER=$($o.PgAdminUser) `
    --from-literal=PGPASSWORD=$PgPassword `
    --from-literal=PGDATABASE=postgres `
    --from-literal=PGSSLMODE=require `
    --dry-run=client -o yaml | kubectl apply -f -
