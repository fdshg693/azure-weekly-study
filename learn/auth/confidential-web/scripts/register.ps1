#Requires -Version 7
# Entra に「コンフィデンシャルな Web アプリ」を 1 つ作る（ユーザーが一度だけ実行）。
# これまでの SPA（パブリッククライアント）との登録上の違いは 2 点：
#   1. リダイレクト URI を **SPA プラットフォームではなく Web プラットフォーム** に登録する
#      （--web-redirect-uris）。Web プラットフォームはクライアントシークレットでの認証を前提とする。
#   2. **クライアントシークレット** を発行する（az ad app credential reset）。これが秘密＝資格情報。
# 自前 API は持たず、本人確認（openid/profile/email）＋ Graph User.Read を **動的同意** で消費するだけなので、
# requiredResourceAccess の事前設定は不要（サインイン時にユーザーが同意する）。
# サインイン／同意のためにサービス プリンシパル（エンタープライズ アプリ）も作る。
$ErrorActionPreference = 'Stop'

$appName  = 'confidential-web'
$redirect = 'http://localhost:3000/auth/callback'  # ★ Web プラットフォーム（SPA ではない）

Write-Host '① コンフィデンシャルな Web アプリのアプリ登録を作成中...' -ForegroundColor Cyan
# --web-redirect-uris で Web プラットフォームに redirect URI を登録する（SPA 用の --spa-redirect-uris とは別物）。
$app = az ad app create `
    --display-name $appName `
    --sign-in-audience AzureADMyOrg `
    --web-redirect-uris $redirect `
    --query '{appId:appId,id:id}' -o json | ConvertFrom-Json

Write-Host '② クライアントシークレットを発行中...' -ForegroundColor Cyan
# ★ これがコンフィデンシャルクライアントの資格情報。値は **この一度だけ** 表示される（後から再表示不可）。
$cred = az ad app credential reset `
    --id $app.appId `
    --display-name 'confidential-web-secret' `
    --years 1 `
    --append `
    --query '{password:password}' -o json | ConvertFrom-Json

Write-Host '③ サービス プリンシパル（エンタープライズ アプリ）を作成中...' -ForegroundColor Cyan
az ad sp create --id $app.appId | Out-Null

Write-Host "`n--- .env に設定する値 ---" -ForegroundColor Green
Write-Host "  CLIENT_ID     = $($app.appId)"
Write-Host "  CLIENT_SECRET = $($cred.password)"
Write-Host '  TENANT_ID     = （task tenant の出力）'
Write-Host "`n⚠ CLIENT_SECRET は今だけ表示されます。すぐ .env に控えてください（.gitignore 済み）。" -ForegroundColor Yellow
Write-Host '  REDIRECT_URI は既定（http://localhost:3000/auth/callback）で OK です。' -ForegroundColor Yellow
