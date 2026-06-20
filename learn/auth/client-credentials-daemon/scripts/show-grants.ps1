#Requires -Version 7
# デーモンのアプリに今どんなアプリケーション許可が付いているかを表示する（grant / revoke の確認用）。
# Graph: デーモン SP の appRoleAssignments を一覧し、各 appRoleId を API 側の定義名に解決して見せる。
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"
$e = Read-DotEnv

$apiApp   = az ad app show --id $e.API_CLIENT_ID | ConvertFrom-Json
$daemonSp = az ad sp show  --id $e.CLIENT_ID     | ConvertFrom-Json
$assignments = az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$($daemonSp.id)/appRoleAssignments" | ConvertFrom-Json

Write-Host "デーモン '$($daemonSp.displayName)' に付与中のアプリケーション許可:" -ForegroundColor Cyan
if (-not $assignments.value) {
    Write-Host '  （なし）— /api/tasks は 403 になります。task grant で付与してください。' -ForegroundColor Yellow
    return
}
foreach ($a in $assignments.value) {
    $name = ($apiApp.appRoles | Where-Object { $_.id -eq $a.appRoleId }).value
    Write-Host "  - $($name ?? $a.appRoleId)  →  リソース: $($a.resourceDisplayName)"
}
