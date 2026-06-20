# ConfigMap(app-config) の 1 キーを書き換える (merge patch なので他キーは保持)。
# 注意: これだけでは反映されない。env は Pod 起動時に固定されるため、
# 続けて 'just config-reload' (rollout restart) で Pod を入れ替える必要がある。
param(
    [Parameter(Mandatory = $true)][string]$Key,
    [Parameter(Mandatory = $true)][string]$Value,
    [string]$Namespace = 'config-rollout'
)

# ハッシュテーブル → JSON で patch 本文を組み立てる (手書き JSON の引用符地獄を避ける)。
$patch = @{ data = @{ $Key = $Value } } | ConvertTo-Json -Compress
kubectl patch configmap app-config -n $Namespace --type merge -p $patch

Write-Host "app-config の $Key を更新しました。反映には 'just config-reload' (Pod 入れ替え) が必要です。"
