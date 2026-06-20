# 消費者 UAMI 本人を主語にした「AcrPull を外すと pull できなくなる」体感 (Step 1 から持ち越した宿題)。
#   registry が作った消費者 UAMI の AcrPull ロールを ACR スコープで付け外しする。
#   on  : AcrPull を付与 (registry の既定状態に戻す)
#   off : AcrPull を剥奪 → この UAMI で pull する ACI は次回 pull 時に 403 で失敗する
#
# 観察の流れ (README の実験3 参照):
#   1) task acrpull-off       … AcrPull を剥奪 (反映に数十秒)
#   2) task recreate          … ACI を作り直す (pull は起動時に走るので、作り直して再 pull させる)
#   3) task show              … events に "Failed to pull image" / 401|403 が出る
#   4) task acrpull-on → recreate → show … 今度は Pulled/Started に戻る
#
# 注意: ここで触る AcrPull は registry の Bicep が定義した割り当てそのもの。
#       registry 側で再 deploy すると元に戻る (冪等)。認証(誰か)はそのまま・認可(AcrPull)だけ動かす実験。
param(
    [Parameter(Mandatory)][ValidateSet('on', 'off')][string]$Action
)

. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$reg = Get-RegistryOutputs

# AcrPull は ACR リソースをスコープに割り当てる。ACR の resource id を取得。
$acrId = az acr show --name $reg.AcrName --resource-group $cfg.RegistryRG --query id -o tsv

if ($Action -eq 'off') {
    Write-Host "AcrPull を剥奪: principal=$($reg.UamiPrincipalId) scope=ACR" -ForegroundColor Cyan
    az role assignment delete --assignee $reg.UamiPrincipalId --role AcrPull --scope $acrId
    Write-Host "剥奪しました。RBAC 反映に数十秒。task recreate → task show で 403 を確認してください。" -ForegroundColor Yellow
}
else {
    Write-Host "AcrPull を付与: principal=$($reg.UamiPrincipalId) scope=ACR" -ForegroundColor Cyan
    # UAMI の principal なので type を明示。冪等 (既にあれば既存が使われる)。
    az role assignment create `
        --assignee-object-id $reg.UamiPrincipalId `
        --assignee-principal-type ServicePrincipal `
        --role AcrPull `
        --scope $acrId
    Write-Host "付与しました。RBAC 反映に数十秒。task recreate → task probe で復活を確認してください。" -ForegroundColor Yellow
}
