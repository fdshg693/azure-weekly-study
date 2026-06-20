# 特定の Container Group だけを削除する (RG は残す)。
# ACI は per-second 課金なので、コンテナグループを消した瞬間に課金が止まる
#   = 「使い捨ての中間形」(vm の deallocate / automate の Job と対比)。
#
# ★削除の単位は「Container Group」であって「コンテナ」ではない。
#   グループを消すと中のコンテナは全部消える (コンテナ 1 個だけ消す API は無い)。
#   例: CG=cg-aci-sidecar を渡すと web+sidecar の 2 コンテナが両方消える。
#   既定の cg-aci-web を消しても、別グループの cg-aci-restart / cg-aci-sidecar は残る
#   (＝web を消しても「全部」は消えない)。全消しは RG ごとの destroy。
param(
    [string]$Cg = ''   # 既定は web グループ。restart/sidecar の cg 名を渡せばそのグループ単位で削除
)

. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$name = if ($Cg) { $Cg } else { "cg-$($cfg.Prefix)-web" }

Write-Host "Container Group を削除 (課金停止): $name" -ForegroundColor Cyan
az container delete --resource-group $cfg.ResourceGroup --name $name --yes
