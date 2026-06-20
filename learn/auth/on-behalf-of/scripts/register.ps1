#Requires -Version 7
# Entra に「下流 API(B)」「中間 API(A)」「SPA」の 3 つのアプリ登録を作成・配線する（ユーザーが一度だけ実行）。
#
# 多段呼び出し（SPA → API A → API B）を成立させるための登録の肝：
#   - 下流 API(B)：identifierUris=api://<B>、requestedAccessTokenVersion=2、
#                  委任スコープ access_as_user を Expose する。普通のリソースサーバー（api-protect と同じ形）。
#   - 中間 API(A)：二役を持つのがこのプロジェクトの新しさ。
#                  (1) リソースサーバーとして identifierUris=api://<A>＋委任スコープ access_as_user を Expose（SPA が呼ぶ）。
#                  (2) コンフィデンシャルクライアントとして B への requiredResourceAccess(type=Scope)＋クライアントシークレット。
#                      → 受け取ったユーザートークンを OBO 交換して B を呼ぶには、A 自身が秘密を持つ必要がある。
#   - SPA       ：SPA プラットフォームに redirect URI、A の access_as_user への requiredResourceAccess(type=Scope)。
#                  ※ SPA は A しか知らない。B の存在は SPA からは見えない（多段の各段は「次の段」だけ知る）。
#
# az ad app create は SPA / Expose an API / requiredResourceAccess 用フラグを持たないため、作成後に Graph を az rest で PATCH する。
# トークン要求と委任同意の割り当て先が SP なので、3 アプリすべてに SP を作る。
#
# ★ 実際の「A→B の委任許可への管理者同意」はここではしない。register 直後は OBO 交換が AADSTS65001（要同意）で失敗する。
#   そのうえで 'task consent' を実行して OBO が通るようになるのを観察する（= 中間層の委任同意の出し入れ）。
$ErrorActionPreference = 'Stop'

$apiBName = 'on-behalf-of-api-downstream'
$apiAName = 'on-behalf-of-api-middle'
$spaName  = 'on-behalf-of-spa'
$redirect = 'http://localhost:5173'

# 委任スコープの GUID を 1 プロセス内で発番し、API 定義と「呼ぶ側」の requiredResourceAccess で共有する。
$scopeBId = [guid]::NewGuid().Guid  # B が Expose する access_as_user（A が要求する）
$scopeAId = [guid]::NewGuid().Guid  # A が Expose する access_as_user（SPA が要求する）

# 委任スコープ定義を作る小さなヘルパー（B と A で同形）。
function New-DelegatedScope([string]$id) {
    @{
        id = $id; value = 'access_as_user'; type = 'User'; isEnabled = $true
        adminConsentDisplayName = 'API にユーザーとしてアクセス'
        adminConsentDescription = 'サインイン中のユーザーとして API へアクセスすることを許可します。'
        userConsentDisplayName  = 'API にあなたとしてアクセス'
        userConsentDescription  = 'あなたとして API へアクセスすることを許可します。'
    }
}

# Graph を PATCH する小さなヘルパー（一時ファイル経由。日本語・入れ子を安全に送るため）。
function Patch-Application([string]$objectId, $bodyObj) {
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Encoding utf8 -Value ($bodyObj | ConvertTo-Json -Depth 12)
    az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$objectId" --headers 'Content-Type=application/json' --body "@$tmp" | Out-Null
    Remove-Item $tmp
}

# === ① 下流 API(B) ===
Write-Host '① 下流 API(B) のアプリ登録を作成中...' -ForegroundColor Cyan
$apiB = az ad app create --display-name $apiBName --sign-in-audience AzureADMyOrg --query '{appId:appId,id:id}' -o json | ConvertFrom-Json

Patch-Application $apiB.id @{
    identifierUris = @("api://$($apiB.appId)")
    api = @{
        requestedAccessTokenVersion = 2
        oauth2PermissionScopes = @( New-DelegatedScope $scopeBId )
    }
}
Write-Host '  下流 API(B) のサービス プリンシパルを作成中...' -ForegroundColor Cyan
az ad sp create --id $apiB.appId | Out-Null

# === ② 中間 API(A)：リソースサーバー兼コンフィデンシャルクライアント ===
Write-Host '② 中間 API(A) のアプリ登録を作成中...' -ForegroundColor Cyan
$apiA = az ad app create --display-name $apiAName --sign-in-audience AzureADMyOrg --query '{appId:appId,id:id}' -o json | ConvertFrom-Json

Patch-Application $apiA.id @{
    identifierUris = @("api://$($apiA.appId)")
    api = @{
        requestedAccessTokenVersion = 2
        oauth2PermissionScopes = @( New-DelegatedScope $scopeAId )  # SPA が要求する A のスコープ
    }
    # A は「B を呼ぶクライアント」でもある：B の access_as_user を委任(type=Scope)で要求する。
    #   この requiredResourceAccess があるからこそ、'task consent' で A→B の委任同意を与えられる。
    requiredResourceAccess = @(
        @{ resourceAppId = $apiB.appId; resourceAccess = @(@{ id = $scopeBId; type = 'Scope' }) }
    )
}
Write-Host '  中間 API(A) のサービス プリンシパルを作成中...' -ForegroundColor Cyan
az ad sp create --id $apiA.appId | Out-Null

Write-Host '  中間 API(A) のクライアントシークレットを発行中...' -ForegroundColor Cyan
# ★ confidential-web と同じ「アプリのパスワード」。値は **この一度だけ** 表示される（後から再表示不可）。
#   用途は OBO 交換：A が token エンドポイントに「このユーザートークンを B 宛トークンに替えて」と頼むときの資格情報。
$cred = az ad app credential reset `
    --id $apiA.appId `
    --display-name 'on-behalf-of-api-middle-secret' `
    --years 1 `
    --append `
    --query '{password:password}' -o json | ConvertFrom-Json

# === ③ SPA ===
Write-Host '③ SPA のアプリ登録を作成中...' -ForegroundColor Cyan
$spa = az ad app create --display-name $spaName --sign-in-audience AzureADMyOrg --query '{appId:appId,id:id}' -o json | ConvertFrom-Json

Patch-Application $spa.id @{
    spa = @{ redirectUris = @($redirect) }
    # SPA は A の access_as_user だけを要求する。B のことは知らない（多段の各段は次の段だけ知る）。
    requiredResourceAccess = @(
        @{ resourceAppId = $apiA.appId; resourceAccess = @(@{ id = $scopeAId; type = 'Scope' }) }
    )
}
Write-Host '  SPA のサービス プリンシパルを作成中...' -ForegroundColor Cyan
az ad sp create --id $spa.appId | Out-Null

Write-Host "`n--- .env に設定する値 ---" -ForegroundColor Green
Write-Host "  TENANT_ID          = （task tenant の出力）"
Write-Host "  SPA_CLIENT_ID      = $($spa.appId)"
Write-Host "  API_A_CLIENT_ID    = $($apiA.appId)        # 中間 API（SPA が呼ぶ相手）"
Write-Host "  API_A_CLIENT_SECRET= $($cred.password)"
Write-Host "  API_B_CLIENT_ID    = $($apiB.appId)        # 下流 API（A が OBO で呼ぶ相手）"
Write-Host "`n⚠ API_A_CLIENT_SECRET は今だけ表示されます。すぐ .env に控えてください（.gitignore 済み）。" -ForegroundColor Yellow
Write-Host "次は 'task consent' で A→B の委任許可に管理者同意を与えてください。" -ForegroundColor Yellow
Write-Host "consent 前は OBO 交換が AADSTS65001（要同意）で失敗します（= /api/chain-obo が 502 を返す）。" -ForegroundColor Yellow
