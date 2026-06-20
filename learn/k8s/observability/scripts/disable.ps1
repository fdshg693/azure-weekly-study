# 監視まわりを片付けて課金を止める。
#   - マネージド Prometheus を無効化
#   - Container Insights アドオンを無効化
#   - Managed Grafana を削除 (インスタンス課金を止める最重要ポイント)
# Azure Monitor / Log Analytics ワークスペースは残ることがあるので、不要なら
# Portal から手動で削除する (空なら課金はほぼ無し)。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$GrafanaName = '',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$aks = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).AksName

if (-not $GrafanaName) {
    $GrafanaName = ("amg-$aks").Substring(0, [Math]::Min(23, "amg-$aks".Length))
}

Write-Host "マネージド Prometheus を無効化..." -ForegroundColor Cyan
az aks update --name $aks --resource-group $ResourceGroup --disable-azure-monitor-metrics

Write-Host "Container Insights アドオンを無効化..." -ForegroundColor Cyan
az aks disable-addons --addons monitoring --name $aks --resource-group $ResourceGroup

Write-Host "Managed Grafana '$GrafanaName' を削除 (課金停止)..." -ForegroundColor Yellow
az grafana delete --name $GrafanaName --resource-group $ResourceGroup --yes --only-show-errors

Write-Host "完了。Azure Monitor / Log Analytics ワークスペースが残る場合は不要なら Portal から削除してください。" -ForegroundColor Green
