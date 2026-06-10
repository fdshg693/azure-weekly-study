#Requires -Version 7
# 現在サインイン中のユーザーに割り当て済みの（この API の）App ロールを一覧する。
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"
$e = Read-DotEnv

$apiApp = az ad app show --id $e.API_CLIENT_ID | ConvertFrom-Json
$map = @{}
foreach ($r in $apiApp.appRoles) { $map[$r.id] = $r.value }

$me = az ad signed-in-user show | ConvertFrom-Json
$assignments = az rest --method GET --url "https://graph.microsoft.com/v1.0/users/$($me.id)/appRoleAssignments" | ConvertFrom-Json
$mine = $assignments.value | Where-Object { $map.ContainsKey($_.appRoleId) } | ForEach-Object { $map[$_.appRoleId] }

Write-Host "ユーザー $($me.userPrincipalName) に割り当て済みの App ロール:" -ForegroundColor Cyan
if ($mine) {
    $mine | ForEach-Object { Write-Host "  - $_" }
} else {
    Write-Host '  （なし）App ロールが無いと roles クレームは出ず、Tasks.* エンドポイントは 403 になります。' -ForegroundColor Yellow
}
