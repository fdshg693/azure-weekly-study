<#
.SYNOPSIS
  OBO チャットの「別ユーザーでログインすると結果が変わる」体験用に、
  Entra ID のテストユーザーを作成 / 確認 / 削除する。

.DESCRIPTION
  チャットの get_user_profile ツールは OBO でサインインユーザー本人の Graph /me を
  返す。つまり「誰でログインしたか」で AI の答えが変わる。これを体験するために、
  管理者（自分）とは別のテストユーザーを 1 本のスクリプトで用意/後片付けする。

    -Action create  … テストユーザーを作成し、UPN と初期パスワードを表示
                       （givenName/jobTitle/officeLocation も設定し、モックや自分と
                        見分けが付くようにする）
    -Action show    … テストユーザーの現在のプロフィールを表示（読み取り専用）
    -Action delete  … テストユーザーを削除（後片付け）

  使い方の流れ:
    1) just user-create            # テストユーザー作成（UPN/パスワードが表示される）
    2) ブラウザのシークレットウィンドウでアプリを開く
       → 「OBO でサインイン（チャット用）」から表示された UPN/パスワードでサインイン
       → 初回は User.Read / access_as_user への同意画面が出る（ユーザー同意で OK）
    3) チャットで「私の名前と部署は？」と聞く
       → 自分でログインしたときと違う、テストユーザーの情報が返る
    4) just user-delete            # 後片付け

.NOTES
  - ユーザーの作成/削除には、サインイン中の自分にディレクトリ権限
    （User Administrator 相当）が必要。権限が無いと az が Authorization 系エラーを返す。
  - 新規ユーザーは *.onmicrosoft.com の初期ドメイン上に作る（パスワード運用が確実なため）。
  - テナントが MFA / 条件付きアクセスを強制している場合、サインインに追加手順が要ることがある。
  - パスワードはコンソールに平文表示する（学習用の使い捨てユーザー前提）。
#>
param(
  [ValidateSet("create", "show", "delete")]
  [string] $Action = "create",

  # 既定のテストユーザー識別子（mailNickname）。UPN は <nick>@<初期ドメイン> になる。
  [string] $MailNickname = "chatbot-test-user",
  [string] $DisplayName  = "テスト 太郎"
)

$ErrorActionPreference = "Stop"

# ----------------------------------------------------------------------------
# 前提: az ログイン確認 & 新規ユーザーを作る初期ドメイン（*.onmicrosoft.com）を解決
# ----------------------------------------------------------------------------
$tenant = az account show --query tenantId -o tsv 2>$null
if (-not $tenant) {
  throw "az にログインしていません。先に 'az login' を実行してください。"
}

# テナントの初期ドメイン（isInitial = *.onmicrosoft.com）を取得。
# 取れない場合は既定ドメイン → サインインユーザーの UPN ドメインの順でフォールバック。
function Resolve-Domain {
  try {
    $domains = az rest --method GET --uri "https://graph.microsoft.com/v1.0/domains" 2>$null | ConvertFrom-Json
    $d = ($domains.value | Where-Object { $_.isInitial } | Select-Object -First 1).id
    if (-not $d) { $d = ($domains.value | Where-Object { $_.isDefault } | Select-Object -First 1).id }
    if ($d) { return $d }
  } catch { }
  $myUpn = az ad signed-in-user show --query userPrincipalName -o tsv 2>$null
  if ($myUpn -and $myUpn.Contains("@")) { return $myUpn.Split("@")[-1] }
  throw "テスト用ドメインを解決できませんでした（Graph domains を読めず、UPN からも取得不可）。"
}

$domain = Resolve-Domain
$upn    = "$MailNickname@$domain"

Write-Host "対象テナント   : $tenant" -ForegroundColor DarkGray
Write-Host "対象ユーザー   : $upn" -ForegroundColor DarkGray
Write-Host ""

# Azure AD のパスワード要件（4 種のうち 3 種以上）を満たすランダムパスワードを生成
function New-RandomPassword {
  $upper  = (65..90)  | Get-Random -Count 4 | ForEach-Object { [char]$_ }
  $lower  = (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ }
  $digit  = (48..57)  | Get-Random -Count 3 | ForEach-Object { [char]$_ }
  $symbol = "!", "@", "#", "%", "*", "-", "_" | Get-Random -Count 2
  $all    = @($upper + $lower + $digit + $symbol)
  return -join ($all | Get-Random -Count $all.Count)
}

# /users/{id} を PATCH してプロフィール項目を埋める（az ad user create では設定できない項目用）
function Set-UserProfileFields {
  param([Parameter(Mandatory)] [string] $UserId, [Parameter(Mandatory)] [hashtable] $Body)
  $tmp = Join-Path $env:TEMP ("user-patch-" + [guid]::NewGuid().ToString() + ".json")
  try {
    $Body | ConvertTo-Json -Depth 10 | Set-Content -Path $tmp -Encoding utf8
    az rest --method PATCH `
      --uri "https://graph.microsoft.com/v1.0/users/$UserId" `
      --headers "Content-Type=application/json" `
      --body "@$tmp" | Out-Null
  }
  finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
  }
}

switch ($Action) {
  "create" {
    # 既存チェック（冪等性のため）。既にあれば作り直さず案内のみ。
    $existing = az ad user show --id $upn --query id -o tsv 2>$null
    if ($existing) {
      Write-Host "⚠️  既に '$upn' は存在します。作り直す場合は先に 'just user-delete' してください。" -ForegroundColor Yellow
      break
    }

    $password = New-RandomPassword

    Write-Host "==> テストユーザーを作成..." -ForegroundColor Cyan
    # --force-change-password-next-sign-in false: 初回サインインでのパスワード変更を求めない
    # （OBO サインイン体験をスムーズにするため。テナントポリシーで拒否される場合あり）
    $created = az ad user create `
      --display-name $DisplayName `
      --user-principal-name $upn `
      --mail-nickname $MailNickname `
      --password $password `
      --force-change-password-next-sign-in false | ConvertFrom-Json

    # モック（山田 太郎 / 東京）や自分の本物プロフィールと見分けが付くよう、項目を設定。
    Write-Host "==> プロフィール項目（部署・勤務地など）を設定..." -ForegroundColor Cyan
    Set-UserProfileFields -UserId $created.id -Body @{
      givenName      = "太郎"
      surname        = "テスト"
      jobTitle       = "OBO 検証用テストユーザー"
      officeLocation = "大阪オフィス"
      mobilePhone    = "+81 90-1234-5678"
    }

    Write-Host ""
    Write-Host "✅ テストユーザーを作成しました" -ForegroundColor Green
    Write-Host "   UPN         : $upn"
    Write-Host "   パスワード  : $password" -ForegroundColor Yellow
    Write-Host "   表示名      : $DisplayName / 部署: OBO 検証用テストユーザー / 勤務地: 大阪オフィス"
    Write-Host ""
    Write-Host "次のステップ:" -ForegroundColor Yellow
    Write-Host "   1) ブラウザのシークレットウィンドウでアプリを開く（自分のセッションと混ざらないように）"
    Write-Host "   2) 「OBO でサインイン（チャット用）」から上記 UPN / パスワードでサインイン"
    Write-Host "      ※ 初回は User.Read / access_as_user への同意画面が出る → 同意で OK"
    Write-Host "   3) チャットで「私の名前と部署、勤務地は？」と質問 → テストユーザーの情報が返る"
    Write-Host "   4) 後片付け: just user-delete"
  }

  "show" {
    $user = az ad user show --id $upn 2>$null | ConvertFrom-Json
    if (-not $user) {
      Write-Host "⛔ '$upn' は存在しません（まだ作成していない / 既に削除済み）。" -ForegroundColor Yellow
      Write-Host "   作成: just user-create" -ForegroundColor DarkGray
      break
    }
    Write-Host "✅ テストユーザーの現在のプロフィール:" -ForegroundColor Green
    Write-Host "   displayName    : $($user.displayName)"
    Write-Host "   givenName      : $($user.givenName)"
    Write-Host "   surname        : $($user.surname)"
    Write-Host "   userPrincipalName: $($user.userPrincipalName)"
    Write-Host "   mail           : $($user.mail)"
    Write-Host "   jobTitle       : $($user.jobTitle)"
    Write-Host "   officeLocation : $($user.officeLocation)"
    Write-Host "   mobilePhone    : $($user.mobilePhone)"
    Write-Host ""
    Write-Host "このユーザーでログインすると、チャットの get_user_profile はこの値を返す。" -ForegroundColor DarkGray
  }

  "delete" {
    $existing = az ad user show --id $upn --query id -o tsv 2>$null
    if (-not $existing) {
      Write-Host "⛔ '$upn' は存在しません（既に削除済み？）。" -ForegroundColor Yellow
      break
    }
    az ad user delete --id $upn | Out-Null
    Write-Host "🗑️  テストユーザー '$upn' を削除しました。" -ForegroundColor Yellow
  }
}

Write-Host ""
