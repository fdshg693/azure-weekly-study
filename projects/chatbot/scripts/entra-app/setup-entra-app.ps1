<#
.SYNOPSIS
  チャットボットの Entra ID 認証（/profile・/profile-obo）に必要な
  App Registration を az CLI で作成 / 更新する。

.DESCRIPTION
  これまで Azure ポータルで手動だった以下をすべて自動化する:
    - App Registration の作成（シングルテナント）
    - Web リダイレクト URI（/auth/redirect, /auth/redirect-obo, ローカル含む）
    - フロントチャネルログアウト URL
    - クライアントシークレットの発行
    - Microsoft Graph "User.Read"（Delegated）権限の登録
    - Expose an API: Application ID URI(api://<client-id>) と access_as_user スコープ
    - Authorized client applications（自分自身を事前承認）
    - サービスプリンシパル（エンタープライズアプリ）の作成

  取得した値（tenant / client id / secret / session secret）は
  auth.auto.tfvars に書き出すので、その後 `just up` で App Settings に反映できる。
  auth.auto.tfvars は .gitignore 済み（*.tfvars）なのでコミットされない。

.NOTES
  再実行は安全（冪等）。既存アプリがあれば再利用し、access_as_user の
  スコープ ID も保持する。ただしクライアントシークレットは毎回再発行される。
#>
param(
  [Parameter(Mandatory)] [string] $WebAppName,
  [string] $DisplayName = "chatbot-graph-demo",
  [string] $TfvarsPath  = "auth.auto.tfvars",
  # ローカル開発用に http://localhost:3000/... のリダイレクト URI も追加する
  [int]    $LocalPort   = 3000,
  [switch] $NoLocalhost
)

. "$PSScriptRoot/../_common.ps1"

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
  # 作成結果の JSON を直接受け取る（一覧の反映待ちレースを避ける）
  $app = az ad app create --display-name $DisplayName --sign-in-audience AzureADMyOrg | ConvertFrom-Json
  Write-Host "    新規作成: appId=$($app.appId)"
}
$appId    = $app.appId
$objectId = $app.id

# ----------------------------------------------------------------------------
# 2. リダイレクト URI / ログアウト URL を組み立て
# ----------------------------------------------------------------------------
$baseUrl   = "https://$WebAppName.azurewebsites.net"
$redirects = @(
  "$baseUrl/auth/redirect"
  "$baseUrl/auth/redirect-obo"
)
if (-not $NoLocalhost) {
  $redirects += "http://localhost:$LocalPort/auth/redirect"
  $redirects += "http://localhost:$LocalPort/auth/redirect-obo"
}

# ----------------------------------------------------------------------------
# 3. access_as_user スコープ ID を決定（既存があれば再利用、無ければ新規生成）
# ----------------------------------------------------------------------------
$existingScope = $app.api.oauth2PermissionScopes | Where-Object { $_.value -eq "access_as_user" } | Select-Object -First 1
$scopeId = if ($existingScope) { $existingScope.id } else { [guid]::NewGuid().ToString() }

# ----------------------------------------------------------------------------
# 4. Graph PATCH で複雑な設定を反映（2 段階に分ける）
#
#    preAuthorizedApplications.delegatedPermissionIds は「既に保存済みの」
#    スコープしか参照できない。同一リクエスト内で公開したスコープは参照不可
#    （InvalidValue になる）。そこで:
#      PATCH(1): identifierUris / web / Graph 権限 / access_as_user スコープ公開
#      PATCH(2): 公開済みスコープを参照して preAuthorizedApplications を設定
# ----------------------------------------------------------------------------
# access_as_user スコープ定義（両 PATCH で使い回す。api を部分更新すると
# oauth2PermissionScopes が消える可能性があるため PATCH(2) でも明示する）
$scopeDefinition = @{
  id                      = $scopeId
  value                   = "access_as_user"
  type                    = "User"   # = Admins and users が同意可能
  isEnabled               = $true
  adminConsentDisplayName = "Access app on behalf of user"
  adminConsentDescription = "Allow the app to access resources on behalf of the signed-in user."
  userConsentDisplayName  = "Access app on your behalf"
  userConsentDescription  = "Allow the app to access resources on your behalf."
}

Write-Host "==> [1/2] リダイレクト URI・Expose an API・Graph 権限を設定..." -ForegroundColor Cyan
Invoke-GraphPatch -ObjectId $objectId -Body @{
  identifierUris = @("api://$appId")
  web = @{
    redirectUris = @($redirects)
    logoutUrl    = "$baseUrl/"
  }
  api = @{
    # Expose an API のスコープ（OBO 用）
    oauth2PermissionScopes = @($scopeDefinition)
  }
  # API permissions: Microsoft Graph の User.Read（Delegated）
  requiredResourceAccess = @(
    @{
      resourceAppId  = $GRAPH_APP_ID
      resourceAccess = @(
        @{ id = $GRAPH_USER_READ_SCOPE_ID; type = "Scope" }
      )
    }
  )
}

Write-Host "==> [2/2] Authorized client applications（自分自身を事前承認）を設定..." -ForegroundColor Cyan
Invoke-GraphPatch -ObjectId $objectId -Body @{
  api = @{
    # スコープ定義を再掲しつつ、公開済みスコープを参照して事前承認を追加
    oauth2PermissionScopes    = @($scopeDefinition)
    preAuthorizedApplications = @(
      @{
        appId                  = $appId
        delegatedPermissionIds = @($scopeId)
      }
    )
  }
}

# ----------------------------------------------------------------------------
# 5. サービスプリンシパル（エンタープライズアプリ）を用意
#    これが無いと同意の記録（oauth2PermissionGrants）が作られない
# ----------------------------------------------------------------------------
Write-Host "==> サービスプリンシパルを確認/作成..." -ForegroundColor Cyan
$spExists = az ad sp show --id $appId --query id -o tsv 2>$null
if (-not $spExists) {
  az ad sp create --id $appId | Out-Null
  Write-Host "    サービスプリンシパルを作成しました"
}
else {
  Write-Host "    既存のサービスプリンシパルを再利用"
}

# ----------------------------------------------------------------------------
# 6. クライアントシークレットを発行（毎回リセット）
# ----------------------------------------------------------------------------
Write-Host "==> クライアントシークレットを発行..." -ForegroundColor Cyan
$clientSecret = az ad app credential reset --id $appId --display-name "chatbot-secret" --query password -o tsv
$clientSecret = $clientSecret.Trim()

# ----------------------------------------------------------------------------
# 7. express-session 用のランダムシークレットを生成
# ----------------------------------------------------------------------------
$sessionSecret = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 48 | ForEach-Object { [char]$_ })

# ----------------------------------------------------------------------------
# 8. Terraform 変数ファイルに書き出し
# ----------------------------------------------------------------------------
Write-Host "==> $TfvarsPath に値を書き出し..." -ForegroundColor Cyan
$tfvars = @"
# このファイルは scripts/entra-app/setup-entra-app.ps1 が自動生成しています。
# 機密値を含むため Git にはコミットされません（.gitignore: *.tfvars）。
entra_tenant_id        = "$tenantId"
entra_client_id        = "$appId"
entra_client_secret    = "$clientSecret"
express_session_secret = "$sessionSecret"
"@
Set-Content -Path $TfvarsPath -Value $tfvars -Encoding utf8

# ----------------------------------------------------------------------------
# 完了サマリ
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "✅ App Registration の設定が完了しました" -ForegroundColor Green
Write-Host "   displayName : $DisplayName"
Write-Host "   appId       : $appId"
Write-Host "   tenantId    : $tenantId"
Write-Host "   identifierUri: api://$appId"
Write-Host "   redirectUris:"
$redirects | ForEach-Object { Write-Host "     - $_" }
Write-Host ""
Write-Host "次のステップ:" -ForegroundColor Yellow
Write-Host "   1) just up        # auth.auto.tfvars の値を App Settings に反映"
Write-Host "   2) just auth-show  # 反映後の状態・許可済スコープを確認"
Write-Host "   ※ User.Read は初回サインイン時にユーザー同意で許可されます。"
