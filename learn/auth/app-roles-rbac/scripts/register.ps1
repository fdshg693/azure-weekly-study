#Requires -Version 7
# Entra に「自前 API」と「SPA」の 2 つのアプリ登録を作成・配線する（ユーザーが一度だけ実行）。
# api-protect との違いは、自前 API 側に App ロール（Tasks.Read / Tasks.Write）を定義すること。
#   - 自前 API：identifierUris=api://<appId>、委任スコープ access_as_user（Expose an API）、
#               App ロール Tasks.Read / Tasks.Write（appRoles）、requestedAccessTokenVersion=2。
#   - SPA    ：SPA プラットフォームに redirect URI、上の API スコープへの requiredResourceAccess。
# az ad app create は SPA / Expose an API / appRoles 用フラグを持たないため、作成後に Graph を az rest で PATCH する。
# SP が無いとトークン要求が AADSTS650052 で失敗し、かつ App ロールの割り当て先（リソース）も SP なので、両アプリに SP を作る。
$ErrorActionPreference = 'Stop'

$apiName  = 'app-roles-rbac-api'
$spaName  = 'app-roles-rbac-spa'
$redirect = 'http://localhost:5173'

Write-Host '① 自前 API のアプリ登録を作成中...' -ForegroundColor Cyan
$api = az ad app create --display-name $apiName --sign-in-audience AzureADMyOrg --query '{appId:appId,id:id}' -o json | ConvertFrom-Json

# スコープ／ロールの GUID を 1 プロセス内で発番し、API 定義と SPA の requiredResourceAccess の両方で共有する。
$scopeId     = [guid]::NewGuid().Guid
$readRoleId  = [guid]::NewGuid().Guid
$writeRoleId = [guid]::NewGuid().Guid

$apiBody = @{
    identifierUris = @("api://$($api.appId)")
    api = @{
        requestedAccessTokenVersion = 2
        oauth2PermissionScopes = @(
            @{
                id = $scopeId; value = 'access_as_user'; type = 'User'; isEnabled = $true
                adminConsentDisplayName = 'API にユーザーとしてアクセス'
                adminConsentDescription = 'サインイン中のユーザーとして自前 API へアクセスすることを許可します。'
                userConsentDisplayName  = 'API にあなたとしてアクセス'
                userConsentDescription  = 'あなたとして自前 API へアクセスすることを許可します。'
            }
        )
    }
    # App ロール：ユーザー（人）に割り当てるロール。value がトークンの roles クレームに乗る。
    appRoles = @(
        @{ id = $readRoleId;  allowedMemberTypes = @('User'); value = 'Tasks.Read';  displayName = 'タスクの閲覧'; description = 'タスク一覧を閲覧できる役割'; isEnabled = $true }
        @{ id = $writeRoleId; allowedMemberTypes = @('User'); value = 'Tasks.Write'; displayName = 'タスクの追加'; description = 'タスクを追加できる役割'; isEnabled = $true }
    )
} | ConvertTo-Json -Depth 10

$tmp = New-TemporaryFile
Set-Content -Path $tmp -Encoding utf8 -Value $apiBody
az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$($api.id)" --headers 'Content-Type=application/json' --body "@$tmp" | Out-Null
Remove-Item $tmp

Write-Host '  自前 API のサービス プリンシパルを作成中...' -ForegroundColor Cyan
az ad sp create --id $api.appId | Out-Null

Write-Host '② SPA のアプリ登録を作成中...' -ForegroundColor Cyan
$spa = az ad app create --display-name $spaName --sign-in-audience AzureADMyOrg --query '{appId:appId,id:id}' -o json | ConvertFrom-Json

$spaBody = @{
    spa = @{ redirectUris = @($redirect) }
    requiredResourceAccess = @(
        @{ resourceAppId = $api.appId; resourceAccess = @(@{ id = $scopeId; type = 'Scope' }) }
    )
} | ConvertTo-Json -Depth 8

$tmp = New-TemporaryFile
Set-Content -Path $tmp -Encoding utf8 -Value $spaBody
az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$($spa.id)" --headers 'Content-Type=application/json' --body "@$tmp" | Out-Null
Remove-Item $tmp

Write-Host '  SPA のサービス プリンシパルを作成中...' -ForegroundColor Cyan
az ad sp create --id $spa.appId | Out-Null

Write-Host "`n--- .env に設定する値 ---" -ForegroundColor Green
Write-Host "  API_CLIENT_ID = $($api.appId)"
Write-Host "  SPA_CLIENT_ID = $($spa.appId)"
Write-Host '  TENANT_ID     = （task tenant の出力）'
Write-Host "`n定義した App ロール: Tasks.Read / Tasks.Write" -ForegroundColor Yellow
Write-Host ".env を整えたら 'task assign -- Tasks.Read' などで自分にロールを割り当ててください。" -ForegroundColor Yellow
