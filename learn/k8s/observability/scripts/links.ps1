# 監視ダッシュボードへの入口 (Portal リンク / Grafana URL) をまとめて表示する。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$GrafanaName = '',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$o = Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName
$aksId = az aks show --name $o.AksName --resource-group $ResourceGroup --query id -o tsv

Write-Host "=== Container Insights (Portal) ===" -ForegroundColor Cyan
Write-Host "Portal で開く: AKS '$($o.AksName)' → Monitoring → Insights"
Write-Host "ディープリンク: https://portal.azure.com/#@/resource$aksId/insights"
Write-Host ""

Write-Host "=== Managed Grafana ===" -ForegroundColor Cyan
if (-not $GrafanaName) {
    $GrafanaName = ("amg-$($o.AksName)").Substring(0, [Math]::Min(23, "amg-$($o.AksName)".Length))
}
try {
    $endpoint = az grafana show --name $GrafanaName --resource-group $ResourceGroup --query properties.endpoint -o tsv 2>$null
    if ($endpoint) {
        Write-Host "Grafana: $endpoint"
        Write-Host "  ログイン後 Dashboards → 'Kubernetes / Compute Resources / Namespace (Pods)' 等で observability namespace を選ぶ"
    } else {
        Write-Host "Grafana '$GrafanaName' は未作成。just monitoring-on で作成してください。" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "Grafana '$GrafanaName' は未作成。just monitoring-on で作成してください。" -ForegroundColor DarkGray
}
