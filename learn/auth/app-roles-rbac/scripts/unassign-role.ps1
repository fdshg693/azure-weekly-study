#Requires -Version 7
# 現在サインイン中のユーザーから App ロールの割り当てを解除する（例: task unassign -- Tasks.Write）。
# 出し入れして「同じユーザーでも可否が変わる」を確かめるための逆操作。
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
    throw "App ロール '$Role' が見つかりません"
}

$me = az ad signed-in-user show | ConvertFrom-Json
$assignments = az rest --method GET --url "https://graph.microsoft.com/v1.0/users/$($me.id)/appRoleAssignments" | ConvertFrom-Json
$targets = $assignments.value | Where-Object { $_.appRoleId -eq $roleId }
if (-not $targets) {
    Write-Host "'$Role' は割り当てられていません。" -ForegroundColor Yellow
    return
}
foreach ($t in $targets) {
    az rest --method DELETE --url "https://graph.microsoft.com/v1.0/users/$($me.id)/appRoleAssignments/$($t.id)" | Out-Null
}
Write-Host "'$Role' の割り当てを解除しました。SPA で押し直すと roles から消えます。" -ForegroundColor Green
