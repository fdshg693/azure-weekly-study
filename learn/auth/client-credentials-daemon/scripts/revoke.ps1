#Requires -Version 7
# デーモンのアプリから「アプリケーション許可」を取り消す（grant の逆）。
# Graph: デーモン SP の appRoleAssignments から Tasks.Process.All の割り当てを探して DELETE する。
# 取り消すと、次に取得するトークンの roles から Tasks.Process.All が消え、/api/tasks が 403 に戻る。
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"
$e = Read-DotEnv

$apiApp = az ad app show --id $e.API_CLIENT_ID | ConvertFrom-Json
$roleId = ($apiApp.appRoles | Where-Object { $_.value -eq 'Tasks.Process.All' }).id

$daemonSp = az ad sp show --id $e.CLIENT_ID | ConvertFrom-Json
$assignments = az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$($daemonSp.id)/appRoleAssignments" | ConvertFrom-Json
$target = $assignments.value | Where-Object { $_.appRoleId -eq $roleId }

if (-not $target) {
    Write-Host "付与済みの 'Tasks.Process.All' は見つかりませんでした（既に取り消し済み？）。" -ForegroundColor Yellow
    return
}

foreach ($a in $target) {
    az rest --method DELETE --url "https://graph.microsoft.com/v1.0/servicePrincipals/$($daemonSp.id)/appRoleAssignments/$($a.id)" | Out-Null
}
Write-Host "デーモン '$($daemonSp.displayName)' から 'Tasks.Process.All' を取り消しました。" -ForegroundColor Green
Write-Host "'task run' でトークンを取り直すと roles から消え、/api/tasks が 403 に戻ります。" -ForegroundColor Yellow
