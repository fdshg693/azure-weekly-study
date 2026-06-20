# web の Container Group を作り直す (削除 → deploy)。
# ACI は **起動時にイメージを pull** するため、AcrPull を出し入れした効果を見るには
# 既存を消してから作り直して再 pull させる必要がある (実行中の再デプロイでは再 pull されない)。
param(
    [ValidateSet('Always', 'OnFailure', 'Never')]
    [string]$Policy = 'Always'
)

. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$cgName = "cg-$($cfg.Prefix)-web"

Write-Host "== 既存の $cgName を削除 ==" -ForegroundColor Cyan
az container delete --resource-group $cfg.ResourceGroup --name $cgName --yes 2>$null | Out-Null

Write-Host "== 作り直し (再 pull) ==" -ForegroundColor Cyan
& "$PSScriptRoot\deploy.ps1" -Policy $Policy
