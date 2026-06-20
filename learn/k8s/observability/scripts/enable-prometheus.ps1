# マネージド Prometheus (Azure Monitor managed service for Prometheus) を有効化し、
# Azure Managed Grafana を作成して紐付ける。
#
# !!! 課金注意 !!!
#   - Azure Managed Grafana はインスタンス課金 (時間あたり) が発生する。
#   - マネージド Prometheus もメトリクス取り込み量で課金される。
#   学習が済んだら scripts/disable.ps1 (just monitoring-off) で必ず止める/消すこと。
#
# 流れ:
#   1. amg CLI 拡張を入れる
#   2. Managed Grafana を作成
#   3. `az aks update --enable-azure-monitor-metrics --grafana-resource-id ...` で
#      マネージド Prometheus を有効化。既定の Azure Monitor ワークスペースを自動作成し、
#      Grafana のデータソース登録とロール割り当てまで Azure 側がまとめて行う。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$GrafanaName = '',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$aks = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).AksName

# Grafana 名はサブドメインになるため (ある程度) 一意・23 文字以内。既定は AKS 名から作る。
if (-not $GrafanaName) {
    $GrafanaName = ("amg-$aks").Substring(0, [Math]::Min(23, "amg-$aks".Length))
}

Write-Host "amg CLI 拡張を確認..." -ForegroundColor Cyan
az extension add --name amg --only-show-errors --upgrade

Write-Host "Managed Grafana '$GrafanaName' を作成 (課金あり)..." -ForegroundColor Yellow
az grafana create --name $GrafanaName --resource-group $ResourceGroup --only-show-errors
$grafanaId = az grafana show --name $GrafanaName --resource-group $ResourceGroup --query id -o tsv

Write-Host "マネージド Prometheus を有効化し Grafana を紐付け (Azure Monitor ワークスペースは自動作成)..." -ForegroundColor Cyan
az aks update --name $aks --resource-group $ResourceGroup `
    --enable-azure-monitor-metrics `
    --grafana-resource-id $grafanaId

$endpoint = az grafana show --name $GrafanaName --resource-group $ResourceGroup --query properties.endpoint -o tsv
Write-Host ""
Write-Host "完了。Grafana エンドポイント: $endpoint" -ForegroundColor Green
Write-Host "  → ログイン後、左メニューの Dashboards に AKS / Kubernetes の既定ダッシュボードが入っています。" -ForegroundColor Green
Write-Host "  片付けるときは: just monitoring-off -GrafanaName $GrafanaName" -ForegroundColor DarkGray
