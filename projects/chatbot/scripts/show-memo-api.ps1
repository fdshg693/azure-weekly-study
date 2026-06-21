<#
.SYNOPSIS
  共有メモ API（chatbot-memo-api）の App Registration と app role 割り当て状況を表示する（読み取り専用）。

.DESCRIPTION
  - App Registration の appId / identifierUris / app role 定義
  - Web App の MI に Memo.ReadWrite が割り当たっているか
  を確認する。割り当てを外して 403 を再現したかどうかの確認に使う。
#>
param(
  [string] $DisplayName    = "chatbot-memo-api",
  [string] $WebAppName     = "webapp-chatbot-dev-seiwan",
  [string] $ResourceGroup  = "rg-chatbot-dev-seiwan",
  [string] $RoleValue      = "Memo.ReadWrite"
)

. "$PSScriptRoot/_common.ps1"

$app = Find-EntraApp -DisplayName $DisplayName
if (-not $app) {
  Write-Host "App Registration '$DisplayName' は存在しません（未セットアップ）。" -ForegroundColor Yellow
  return
}

Write-Host "App Registration" -ForegroundColor Cyan
Write-Host "  displayName  : $($app.displayName)"
Write-Host "  appId        : $($app.appId)"
Write-Host "  identifierUris: $($app.identifierUris -join ', ')"

$role = $app.appRoles | Where-Object { $_.value -eq $RoleValue } | Select-Object -First 1
if ($role) {
  Write-Host "  app role     : $($role.value) (id=$($role.id), enabled=$($role.isEnabled))"
} else {
  Write-Host "  app role     : $RoleValue は未定義" -ForegroundColor Yellow
}

# リソース SP と割り当て状況
$resourceSpId = az ad sp show --id $($app.appId) --query id -o tsv 2>$null
if (-not $resourceSpId) {
  Write-Host "  サービスプリンシパル: 未作成" -ForegroundColor Yellow
  return
}
$resourceSpId = $resourceSpId.Trim()

$webAppMiPrincipalId = az webapp identity show --name $WebAppName --resource-group $ResourceGroup --query principalId -o tsv 2>$null
Write-Host ""
Write-Host "app role 割り当て（appRoleAssignedTo）" -ForegroundColor Cyan
$assignments = az rest --method GET `
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$resourceSpId/appRoleAssignedTo" 2>$null | ConvertFrom-Json

if (-not $assignments -or $assignments.value.Count -eq 0) {
  Write-Host "  割り当てなし" -ForegroundColor Yellow
} else {
  foreach ($a in $assignments.value) {
    $mark = if ($webAppMiPrincipalId -and $a.principalId -eq $webAppMiPrincipalId.Trim()) { " <- Web App MI" } else { "" }
    Write-Host "  principal=$($a.principalDisplayName) ($($a.principalId))$mark"
  }
}
