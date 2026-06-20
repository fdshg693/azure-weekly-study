#Requires -Version 7
# デーモンのアプリに「アプリケーション許可」を付与する（= このフローでの管理者同意）。
#
# app-roles-rbac では「ユーザーに」ロールを割り当てた（principalId=ユーザー）。
# ここでは「アプリ（デーモンの SP）に」ロールを割り当てる（principalId=デーモンの SP）。これが委任との決定的な違い：
#   委任は「サインインしたユーザーがその場で同意」、アプリケーション許可は「管理者が事前にアプリへ付与」。
# Graph: デーモン SP の appRoleAssignments に { principalId=デーモンSP, resourceId=API の SP, appRoleId } を POST。
# ※ アプリケーション許可の付与には管理者権限（グローバル管理者／特権ロール）が必要。
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"
$e = Read-DotEnv

# API 側の App ロール定義から Tasks.Process.All の GUID を引く。
$apiApp = az ad app show --id $e.API_CLIENT_ID | ConvertFrom-Json
$roleId = ($apiApp.appRoles | Where-Object { $_.value -eq 'Tasks.Process.All' }).id
if (-not $roleId) {
    throw "アプリケーション許可ロール 'Tasks.Process.All' が見つかりません（register.ps1 を実行しましたか）。"
}

$apiSp    = az ad sp show --id $e.API_CLIENT_ID | ConvertFrom-Json  # ロールの提供元（resource）
$daemonSp = az ad sp show --id $e.CLIENT_ID     | ConvertFrom-Json  # ロールの割り当て先（principal＝アプリ自身）

$body = @{ principalId = $daemonSp.id; resourceId = $apiSp.id; appRoleId = $roleId } | ConvertTo-Json
$tmp = New-TemporaryFile
Set-Content -Path $tmp -Encoding utf8 -Value $body
az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$($daemonSp.id)/appRoleAssignments" --headers 'Content-Type=application/json' --body "@$tmp" | Out-Null
Remove-Item $tmp

Write-Host "デーモン '$($daemonSp.displayName)' に 'Tasks.Process.All' を付与しました（アプリケーション許可）。" -ForegroundColor Green
Write-Host "'task run' でトークンを取り直すと roles に Tasks.Process.All が乗り、/api/tasks が 200 になります。" -ForegroundColor Yellow
