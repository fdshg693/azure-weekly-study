#Requires -Version 7
# 現在サインイン中のユーザーに App ロールを割り当てる（例: task assign -- Tasks.Read）。
# 認可（roles）は scp と違い「クライアントが要求」するものではなく「管理者がユーザーに割り当てる」もの。
# Graph: ユーザーの appRoleAssignments に { principalId=ユーザー, resourceId=API の SP, appRoleId } を POST。
# ※ ロールの割り当てには管理者権限（またはアプリ所有者＋十分な権限）が必要なことがある。
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Role
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"
$e = Read-DotEnv

$apiApp = az ad app show --id $e.API_CLIENT_ID | ConvertFrom-Json
$roleId = ($apiApp.appRoles | Where-Object { $_.value -eq $Role }).id
if (-not $roleId) {
    throw "App ロール '$Role' が見つかりません（定義済み: $(($apiApp.appRoles.value) -join ', ')）"
}

$sp = az ad sp show --id $e.API_CLIENT_ID | ConvertFrom-Json
$me = az ad signed-in-user show | ConvertFrom-Json

$body = @{ principalId = $me.id; resourceId = $sp.id; appRoleId = $roleId } | ConvertTo-Json
$tmp = New-TemporaryFile
Set-Content -Path $tmp -Encoding utf8 -Value $body
az rest --method POST --url "https://graph.microsoft.com/v1.0/users/$($me.id)/appRoleAssignments" --headers 'Content-Type=application/json' --body "@$tmp" | Out-Null
Remove-Item $tmp

Write-Host "ユーザー $($me.userPrincipalName) に '$Role' を割り当てました。" -ForegroundColor Green
Write-Host 'SPA でボタンを押し直す（forceRefresh で再取得）と roles に反映されます。' -ForegroundColor Yellow
