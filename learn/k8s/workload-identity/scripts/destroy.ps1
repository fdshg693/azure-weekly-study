# このプロジェクトが作ったものを片付ける。simple のクラスタ/インフラ本体は残す。
#   1. workload-identity 名前空間を削除 (Pod/SA/Service/Ingress)。
#   2. UAMI を PG の Entra 管理者から外す。
#   3. UAMI (と FIC) を削除。
# AKS の OIDC/Workload Identity 有効化や PG の Entra 認証有効化は無害なので戻さない
# (戻したい場合は手動で az aks update --disable-... / --active-directory-auth Disabled)。
param(
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

# 1. k8s 側
kubectl delete namespace $script:WiNamespace --ignore-not-found

# 2 & 3. Azure 側 (UAMI が残っていれば外して消す)
try {
    $pg = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).PgName
    $u  = Get-Uami -ResourceGroup $ResourceGroup
    az postgres flexible-server ad-admin delete --resource-group $ResourceGroup --server-name $pg --object-id $u.PrincipalId --yes
    az identity delete --resource-group $ResourceGroup --name $u.Name
    Write-Host "UAMI '$($u.Name)' と PG 管理者登録を削除しました。"
} catch {
    Write-Host "UAMI は既に無いようです: $($_.Exception.Message)"
}
