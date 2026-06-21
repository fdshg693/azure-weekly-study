<#
.SYNOPSIS
  共有メモ Function を Entra（EasyAuth）で保護し、Web App のマネージド ID に
  app role(Memo.ReadWrite) を割り当てる。

.DESCRIPTION
  「アプリ自身（MI）の権限で保護 API を呼ぶ（アプリ間認証）」を成立させる以下を自動化する:
    - App Registration `chatbot-memo-api` の作成（Function の保護用・aud を定義）
    - Application ID URI（api://<appId>）の設定
    - app role `Memo.ReadWrite`（allowedMemberTypes=Application）の定義
    - サービスプリンシパル（エンタープライズアプリ）の作成
    - Web App のシステム割り当て MI のサービスプリンシパルに上記 app role を割り当て
    - memo_api_app_id を memo.auto.tfvars に書き出し

  appId を memo.auto.tfvars 経由で Terraform に渡すと、Function の EasyAuth が
  有効化され、Web App の MI トークン（aud=api://<appId>, roles=Memo.ReadWrite）だけを通す。

.NOTES
  - 事前に `just up`（Terraform apply）で Web App と Function を作成しておくこと
    （Web App の MI を割り当て先として参照するため）。
  - 再実行は安全（冪等）。app role / 割り当ては既存を再利用する。
#>
param(
  [string] $DisplayName = "chatbot-memo-api",
  # Terraform variables.tf の web_app_name デフォルトと合わせる
  [string] $WebAppName  = "webapp-chatbot-dev-seiwan",
  [string] $ResourceGroup = "rg-chatbot-dev-seiwan",
  [string] $RoleValue   = "Memo.ReadWrite",
  [string] $TfvarsPath  = "memo.auto.tfvars"
)

. "$PSScriptRoot/_common.ps1"

Write-Host "==> テナントとログイン状態を確認..." -ForegroundColor Cyan
$tenantId = Get-TenantId
Write-Host "    tenant: $tenantId"

# ----------------------------------------------------------------------------
# 1. App Registration を取得 or 作成
# ----------------------------------------------------------------------------
Write-Host "==> App Registration '$DisplayName' を確認/作成..." -ForegroundColor Cyan
$app = Find-EntraApp -DisplayName $DisplayName
if ($app) {
  Write-Host "    既存アプリを再利用: appId=$($app.appId)"
}
else {
  $app = az ad app create --display-name $DisplayName --sign-in-audience AzureADMyOrg | ConvertFrom-Json
  Write-Host "    新規作成: appId=$($app.appId)"
}
$appId    = $app.appId
$objectId = $app.id

# ----------------------------------------------------------------------------
# 2. app role(Memo.ReadWrite) の ID を決定（既存があれば再利用）
# ----------------------------------------------------------------------------
$existingRole = $app.appRoles | Where-Object { $_.value -eq $RoleValue } | Select-Object -First 1
$roleId = if ($existingRole) { $existingRole.id } else { [guid]::NewGuid().ToString() }

$roleDefinition = @{
  id                 = $roleId
  value              = $RoleValue
  # アプリ（デーモン/MI）に割り当てる role なので Application。ユーザーには割り当てない。
  allowedMemberTypes = @("Application")
  displayName        = "Read and write shared memos"
  description        = "Allows the app (managed identity) to perform CRUD on shared memos."
  isEnabled          = $true
}

# ----------------------------------------------------------------------------
# 3. Identifier URI（aud）と app role を Graph PATCH で設定
# ----------------------------------------------------------------------------
Write-Host "==> Application ID URI と app role($RoleValue) を設定..." -ForegroundColor Cyan
Invoke-GraphPatch -ObjectId $objectId -Body @{
  identifierUris = @("api://$appId")
  appRoles       = @($roleDefinition)
}

# ----------------------------------------------------------------------------
# 4. このアプリ（リソース側）のサービスプリンシパルを用意
#    app role 割り当ての resourceId として必要。
# ----------------------------------------------------------------------------
Write-Host "==> リソース側サービスプリンシパルを確認/作成..." -ForegroundColor Cyan
$resourceSpId = az ad sp show --id $appId --query id -o tsv 2>$null
if (-not $resourceSpId) {
  az ad sp create --id $appId | Out-Null
  $resourceSpId = az ad sp show --id $appId --query id -o tsv
  Write-Host "    サービスプリンシパルを作成しました"
}
else {
  Write-Host "    既存のサービスプリンシパルを再利用"
}
$resourceSpId = $resourceSpId.Trim()

# ----------------------------------------------------------------------------
# 5. Web App のシステム割り当て MI（呼び出し元）の principal を取得
# ----------------------------------------------------------------------------
Write-Host "==> Web App '$WebAppName' のマネージド ID を取得..." -ForegroundColor Cyan
$webAppMiPrincipalId = az webapp identity show --name $WebAppName --resource-group $ResourceGroup --query principalId -o tsv 2>$null
if (-not $webAppMiPrincipalId) {
  throw "Web App '$WebAppName' のシステム割り当て MI が見つかりません。先に 'just up' でデプロイし、identity を有効化してください。"
}
$webAppMiPrincipalId = $webAppMiPrincipalId.Trim()
Write-Host "    Web App MI principalId: $webAppMiPrincipalId"

# ----------------------------------------------------------------------------
# 6. MI のサービスプリンシパルに app role を割り当て（冪等）
#    POST /servicePrincipals/{resourceSpId}/appRoleAssignedTo
#      principalId = 呼び出し元（Web App MI の SP）
#      resourceId  = リソース（memo-api の SP）
#      appRoleId   = Memo.ReadWrite の id
# ----------------------------------------------------------------------------
Write-Host "==> Web App MI に app role($RoleValue) を割り当て..." -ForegroundColor Cyan
$existingAssignments = az rest --method GET `
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$resourceSpId/appRoleAssignedTo" `
  --query "value[?principalId=='$webAppMiPrincipalId' && appRoleId=='$roleId']" 2>$null | ConvertFrom-Json

if ($existingAssignments -and $existingAssignments.Count -gt 0) {
  Write-Host "    既に割り当て済み（スキップ）"
}
else {
  $assignBody = @{
    principalId = $webAppMiPrincipalId
    resourceId  = $resourceSpId
    appRoleId   = $roleId
  }
  $tmp = Join-Path $env:TEMP ("memo-role-" + [guid]::NewGuid().ToString() + ".json")
  try {
    $assignBody | ConvertTo-Json | Set-Content -Path $tmp -Encoding utf8
    az rest --method POST `
      --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$resourceSpId/appRoleAssignedTo" `
      --headers "Content-Type=application/json" `
      --body "@$tmp" | Out-Null
    Write-Host "    割り当て完了"
  }
  finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
  }
}

# ----------------------------------------------------------------------------
# 7. memo.auto.tfvars に appId を書き出し
# ----------------------------------------------------------------------------
Write-Host "==> $TfvarsPath に memo_api_app_id を書き出し..." -ForegroundColor Cyan
$tfvars = @"
# このファイルは scripts/setup-memo-api.ps1 が自動生成しています。
# *.tfvars は .gitignore 済みなのでコミットされません。
memo_api_app_id = "$appId"
"@
Set-Content -Path $TfvarsPath -Value $tfvars -Encoding utf8

# ----------------------------------------------------------------------------
# 完了サマリ
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "✅ メモ API の Entra 保護設定が完了しました" -ForegroundColor Green
Write-Host "   displayName  : $DisplayName"
Write-Host "   appId        : $appId"
Write-Host "   identifierUri: api://$appId"
Write-Host "   app role     : $RoleValue ($roleId)"
Write-Host ""
Write-Host "次のステップ:" -ForegroundColor Yellow
Write-Host "   1) just apply        # memo.auto.tfvars が反映され Function の EasyAuth が有効化される"
Write-Host "   2) Web App の App Settings に以下を設定（just up 済みでも個別設定が必要）:"
Write-Host "        MEMO_API_BASE_URL = https://<func_app_hostname>"
Write-Host "        MEMO_API_SCOPE    = api://$appId/.default"
Write-Host "      ※ host/url は 'terraform output memo_api_base_url' で取得"
Write-Host "   3) MI への app role 割り当てを外すと 403 になる挙動を体験できます（just memo-api-show で確認）"
