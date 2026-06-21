<#
.SYNOPSIS
  現在の Entra ID App Registration の状態と「許可済みスコープ」を確認する。

.DESCRIPTION
  setup-entra-app.ps1 で作成したアプリの設定が想定どおりかを目視確認するための
  読み取り専用スクリプト。変更は一切行わない。以下を表示する:
    - 基本情報（appId / objectId / サインイン対象 / Application ID URI）
    - リダイレクト URI とログアウト URL
    - Expose an API のスコープ（access_as_user など）
    - Authorized client applications（事前承認済みクライアント）
    - 要求している API permissions（Microsoft Graph User.Read など）
    - クライアントシークレットのメタ情報（値は表示されない / 有効期限のみ）
    - サービスプリンシパルの有無
    - 実際にユーザー/管理者が同意済みのスコープ（oauth2PermissionGrants）
#>
param(
  [string] $DisplayName = "chatbot-graph-demo"
)

. "$PSScriptRoot/../_common.ps1"

function Write-Section {
  param([string] $Title)
  Write-Host ""
  Write-Host "── $Title " -ForegroundColor Cyan -NoNewline
  Write-Host ("─" * [Math]::Max(0, 60 - $Title.Length)) -ForegroundColor DarkGray
}

$app = Find-EntraApp -DisplayName $DisplayName
if (-not $app) {
  Write-Host "App Registration '$DisplayName' は見つかりませんでした。" -ForegroundColor Yellow
  Write-Host "先に 'just auth-setup' を実行してください。"
  exit 0
}
$appId = $app.appId

Write-Section "基本情報"
[pscustomobject]@{
  displayName    = $app.displayName
  appId          = $app.appId
  objectId       = $app.id
  signInAudience = $app.signInAudience
  identifierUris = ($app.identifierUris -join ", ")
} | Format-List

Write-Section "リダイレクト URI / ログアウト URL"
if ($app.web.redirectUris) {
  $app.web.redirectUris | ForEach-Object { Write-Host "  redirect : $_" }
} else {
  Write-Host "  (なし)" -ForegroundColor Yellow
}
Write-Host "  logout   : $($app.web.logoutUrl)"

Write-Section "Expose an API（公開スコープ）"
if ($app.api.oauth2PermissionScopes) {
  $app.api.oauth2PermissionScopes | ForEach-Object {
    $who = if ($_.type -eq "User") { "Admins and users" } else { "Admins only" }
    Write-Host "  - $($_.value)  (enabled=$($_.isEnabled), consent=$who)"
    Write-Host "      id=$($_.id)"
  }
} else {
  Write-Host "  (公開スコープなし)" -ForegroundColor Yellow
}

Write-Section "Authorized client applications（事前承認）"
if ($app.api.preAuthorizedApplications) {
  $app.api.preAuthorizedApplications | ForEach-Object {
    $self = if ($_.appId -eq $appId) { " (= 自分自身)" } else { "" }
    Write-Host "  - clientAppId=$($_.appId)$self"
    Write-Host "      permissions=$($_.delegatedPermissionIds -join ', ')"
  }
} else {
  Write-Host "  (なし)" -ForegroundColor Yellow
}

Write-Section "要求している API permissions"
if ($app.requiredResourceAccess) {
  foreach ($r in $app.requiredResourceAccess) {
    $resName = if ($r.resourceAppId -eq $GRAPH_APP_ID) { "Microsoft Graph" } else { $r.resourceAppId }
    Write-Host "  resource: $resName"
    foreach ($a in $r.resourceAccess) {
      $kind = if ($a.type -eq "Scope") { "Delegated" } else { "Application" }
      $name = if ($a.id -eq $GRAPH_USER_READ_SCOPE_ID) { "User.Read" } else { $a.id }
      Write-Host "    - $name ($kind)"
    }
  }
} else {
  Write-Host "  (なし)" -ForegroundColor Yellow
}

Write-Section "クライアントシークレット（メタ情報のみ）"
$secrets = az ad app credential list --id $appId | ConvertFrom-Json
if ($secrets) {
  $secrets | ForEach-Object {
    Write-Host "  - name=$($_.displayName)  keyId=$($_.keyId)"
    Write-Host "      expires=$($_.endDateTime)"
  }
} else {
  Write-Host "  (シークレットなし)" -ForegroundColor Yellow
}

Write-Section "サービスプリンシパル"
$spId = az ad sp show --id $appId --query id -o tsv 2>$null
if ($spId) {
  Write-Host "  あり: spObjectId=$($spId.Trim())"

  Write-Section "同意済みスコープ（oauth2PermissionGrants）"
  $grants = az rest --method GET `
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($spId.Trim())/oauth2PermissionGrants" `
    | ConvertFrom-Json
  if ($grants.value) {
    foreach ($g in $grants.value) {
      $consent = if ($g.consentType -eq "AllPrincipals") { "管理者同意（テナント全体）" } else { "ユーザー同意" }
      Write-Host "  - scope: $($g.scope)"
      Write-Host "      consentType=$consent"
    }
  } else {
    Write-Host "  まだ誰も同意していません（初回サインイン時に付与されます）" -ForegroundColor Yellow
  }
} else {
  Write-Host "  なし（'just auth-setup' でサービスプリンシパルが作成されます）" -ForegroundColor Yellow
}

Write-Host ""
