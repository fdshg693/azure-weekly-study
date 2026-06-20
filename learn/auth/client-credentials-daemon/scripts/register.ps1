#Requires -Version 7
# Entra に「自前 API」と「デーモン（クライアント）」の 2 つのアプリ登録を作成・配線する（ユーザーが一度だけ実行）。
#
# app-roles-rbac との違いは、ロールの割り当て先が「ユーザー」ではなく「アプリ（の SP）」であること：
#   - 自前 API：identifierUris=api://<appId>、requestedAccessTokenVersion=2、
#               App ロール Tasks.Process.All を allowedMemberTypes=Application（=アプリケーション許可）で定義。
#               委任スコープ（Expose an API / access_as_user）は今回は不要（ユーザーがいないため）。
#   - デーモン：コンフィデンシャルクライアント（クライアントシークレットを発行）。
#               requiredResourceAccess で上の API ロールを type=Role（=アプリケーション許可）として要求。
#               ※ type=Scope なら委任、type=Role ならアプリケーション許可。ここが委任 vs アプリの登録上の分岐点。
# az ad app create は appRoles / requiredResourceAccess 用フラグを持たないため、作成後に Graph を az rest で PATCH する。
# 両アプリに SP を作る（API 側はロール割り当て先のリソース、デーモン側はトークン要求とロール割り当て先の主体になる）。
#
# ★ 実際の「許可付与（管理者同意）」はここではしない。register 直後は roles が無く API は 403 になる。
#   そのうえで 'task grant' を実行して 200 に変わるのを観察する（= アプリケーション許可の出し入れ）。
$ErrorActionPreference = 'Stop'

$apiName    = 'client-credentials-daemon-api'
$daemonName = 'client-credentials-daemon'

Write-Host '① 自前 API のアプリ登録を作成中...' -ForegroundColor Cyan
$api = az ad app create --display-name $apiName --sign-in-audience AzureADMyOrg --query '{appId:appId,id:id}' -o json | ConvertFrom-Json

# アプリケーション許可ロールの GUID を 1 プロセス内で発番し、API 定義とデーモンの requiredResourceAccess で共有する。
$roleId = [guid]::NewGuid().Guid

$apiBody = @{
    identifierUris = @("api://$($api.appId)")
    api = @{ requestedAccessTokenVersion = 2 }
    # App ロール：allowedMemberTypes=Application ＝「アプリ（人ではない）」に割り当てるアプリケーション許可。
    #   value がトークンの roles クレームに乗る。app-roles-rbac の User 向けロールと対比される。
    appRoles = @(
        @{
            id = $roleId; allowedMemberTypes = @('Application'); value = 'Tasks.Process.All'
            displayName = 'タスクの処理（アプリとして）'; description = 'デーモンがユーザー不在で処理待ちタスクにアクセスできるアプリケーション許可'
            isEnabled = $true
        }
    )
} | ConvertTo-Json -Depth 10

$tmp = New-TemporaryFile
Set-Content -Path $tmp -Encoding utf8 -Value $apiBody
az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$($api.id)" --headers 'Content-Type=application/json' --body "@$tmp" | Out-Null
Remove-Item $tmp

Write-Host '  自前 API のサービス プリンシパルを作成中...' -ForegroundColor Cyan
az ad sp create --id $api.appId | Out-Null

Write-Host '② デーモン（コンフィデンシャルクライアント）のアプリ登録を作成中...' -ForegroundColor Cyan
$daemon = az ad app create --display-name $daemonName --sign-in-audience AzureADMyOrg --query '{appId:appId,id:id}' -o json | ConvertFrom-Json

# requiredResourceAccess に type=Role でアプリケーション許可を要求する（type=Scope の委任とは別物）。
$daemonBody = @{
    requiredResourceAccess = @(
        @{ resourceAppId = $api.appId; resourceAccess = @(@{ id = $roleId; type = 'Role' }) }
    )
} | ConvertTo-Json -Depth 8

$tmp = New-TemporaryFile
Set-Content -Path $tmp -Encoding utf8 -Value $daemonBody
az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$($daemon.id)" --headers 'Content-Type=application/json' --body "@$tmp" | Out-Null
Remove-Item $tmp

Write-Host '  デーモンのサービス プリンシパルを作成中...' -ForegroundColor Cyan
az ad sp create --id $daemon.appId | Out-Null

Write-Host '③ デーモンのクライアントシークレットを発行中...' -ForegroundColor Cyan
# ★ confidential-web と同じ「アプリのパスワード」。値は **この一度だけ** 表示される（後から再表示不可）。
#   違いは用途：あちらはユーザーログイン後の交換に使い、こちらはユーザー不在の client credentials に使う。
$cred = az ad app credential reset `
    --id $daemon.appId `
    --display-name 'client-credentials-daemon-secret' `
    --years 1 `
    --append `
    --query '{password:password}' -o json | ConvertFrom-Json

Write-Host "`n--- .env に設定する値 ---" -ForegroundColor Green
Write-Host "  TENANT_ID     = （task tenant の出力）"
Write-Host "  CLIENT_ID     = $($daemon.appId)        # デーモン自身"
Write-Host "  CLIENT_SECRET = $($cred.password)"
Write-Host "  API_CLIENT_ID = $($api.appId)        # 呼ぶ相手の自前 API"
Write-Host "`n⚠ CLIENT_SECRET は今だけ表示されます。すぐ .env に控えてください（.gitignore 済み）。" -ForegroundColor Yellow
Write-Host "定義したアプリケーション許可ロール: Tasks.Process.All（allowedMemberTypes=Application）" -ForegroundColor Yellow
Write-Host "次は 'task grant' で許可を付与（管理者同意）してください。grant 前は API が 403 になります。" -ForegroundColor Yellow
