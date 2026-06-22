# V2 認証フローの動作確認シード。BFF(http://localhost:3000) 経由で
# サインアップ → （ローカル出力された検証リンクを踏む）→ ログイン → 友達追加 まで通す。
# 前提: task local-up / api / functions / bff が起動済み、EMAIL_MODE=local。
param([string]$BaseUrl = "http://localhost:3000")
$ErrorActionPreference = 'Stop'
$proj = Split-Path $PSScriptRoot -Parent
$verifyDir = Join-Path $proj '.verify-links'

# サインアップ（未検証ユーザーを作る＋検証リンクをローカル出力させる）
function Signup($email, $username, $password) {
  Invoke-RestMethod -Uri "$BaseUrl/api/signup" -Method Post -ContentType 'application/json' `
    -Body (@{ email = $email; username = $username; password = $password } | ConvertTo-Json) | Out-Null
  Write-Host "signup: $username <$email>" -ForegroundColor Green
}

# EMAIL_MODE=local が書き出した .verify-links/<email>.txt のリンクを踏む
function Verify($email) {
  $file = Join-Path $verifyDir "$email.txt"
  if (-not (Test-Path $file)) {
    throw "検証リンクが見つかりません: $file （EMAIL_MODE=local で functions が起動済みか確認）"
  }
  $link = (Get-Content $file -Raw).Trim()
  Invoke-WebRequest -Uri $link -UseBasicParsing | Out-Null
  Write-Host "verify: $email -> 検証済み" -ForegroundColor Green
}

# ログインして JWT を取得
function Login($email, $password) {
  $r = Invoke-RestMethod -Uri "$BaseUrl/api/login" -Method Post -ContentType 'application/json' `
    -Body (@{ email = $email; password = $password } | ConvertTo-Json)
  Write-Host "login: $email -> token 取得" -ForegroundColor Cyan
  return $r.token
}

# 友達追加（Bearer トークン必須）
function AddFriend($token, $username) {
  Invoke-RestMethod -Uri "$BaseUrl/api/friends" -Method Post `
    -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' `
    -Body (@{ username = $username } | ConvertTo-Json) | Out-Null
  Write-Host "friend add: -> $username" -ForegroundColor Cyan
}

function Friends($token, $who) {
  $r = Invoke-RestMethod -Uri "$BaseUrl/api/friends" -Headers @{ Authorization = "Bearer $token" }
  $tag = if ($r.cached) { '[cache]' } else { '[fresh]' }
  Write-Host "friends ($who) $tag : $($r.friends -join ', ')" -ForegroundColor Yellow
}

Signup 'alice@example.com' 'alice' 'pass-alice'
Signup 'bob@example.com'   'bob'   'pass-bob'

Verify 'alice@example.com'
Verify 'bob@example.com'

$aliceToken = Login 'alice@example.com' 'pass-alice'

AddFriend $aliceToken 'bob'
Friends $aliceToken 'alice'  # bob が即時に出る（自分の操作→自分のキャッシュ無効化）

Write-Host ""
Write-Host "未検証ログインの拒否も確認できます（検証前に login すると 403）。" -ForegroundColor DarkGray
Write-Host "ブラウザで $BaseUrl を開き、alice/bob でログインして友達リストを体験してください。" -ForegroundColor Cyan
