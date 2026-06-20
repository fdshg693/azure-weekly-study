# Container Insights (Log Analytics ベースのコンテナ監視) を有効化する。
# これは比較的安価な第一歩。CPU/メモリ・Pod 再起動・ログを Portal の
# 「Insights」ブレードで見られるようになる。
#
# --workspace-resource-id を省略すると、既定の Log Analytics ワークスペースを
# 自動作成して紐付ける (学習用にはこれで十分)。
# 既に有効なら az がエラーを返すが、その場合は既に使える状態なので無視してよい。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$aks = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).AksName

Write-Host "Container Insights を有効化します (Log Analytics を自動作成)..." -ForegroundColor Cyan
az aks enable-addons --addons monitoring --name $aks --resource-group $ResourceGroup

Write-Host "完了。数分後に Portal → AKS → Monitoring → Insights でグラフが出始めます。" -ForegroundColor Green
