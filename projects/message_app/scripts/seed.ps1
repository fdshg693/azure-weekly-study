# 動作確認用シード（V2）。BFF(http://localhost:3000) 経由で
# サインアップ → 検証 → ログイン → メッセージ送信 → 会話取得 まで通す。
# V2 ではメッセージ送受信に JWT が要るので、各ユーザーのトークンを取得して使う。
# 前提: task local-up / api / functions / bff 起動済み、EMAIL_MODE=local。
param([string]$BaseUrl = "http://localhost:3000")
$ErrorActionPreference = 'Stop'
$proj = Split-Path $PSScriptRoot -Parent
$verifyDir = Join-Path $proj '.verify-links'

# サインアップ → ローカル検証リンクを踏む → ログインして token を返す（一括）。
function Onboard($email, $username, $password) {
  Invoke-RestMethod -Uri "$BaseUrl/api/signup" -Method Post -ContentType 'application/json' `
    -Body (@{ email = $email; username = $username; password = $password } | ConvertTo-Json) | Out-Null

  $file = Join-Path $verifyDir "$email.txt"
  if (-not (Test-Path $file)) { throw "検証リンクが見つかりません: $file" }
  Invoke-WebRequest -Uri ((Get-Content $file -Raw).Trim()) -UseBasicParsing | Out-Null

  $r = Invoke-RestMethod -Uri "$BaseUrl/api/login" -Method Post -ContentType 'application/json' `
    -Body (@{ email = $email; password = $password } | ConvertTo-Json)
  Write-Host "onboard: $username <$email>" -ForegroundColor Green
  return $r.token
}

# 送信（送信者の Bearer トークンが必要）
function Send($token, $from, $to, $text) {
  Invoke-RestMethod -Uri "$BaseUrl/api/messages" -Method Post `
    -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' `
    -Body (@{ to = $to; text = $text } | ConvertTo-Json) | Out-Null
  Write-Host "send: $from -> $to : $text" -ForegroundColor Cyan
}

# 会話取得（閲覧者の Bearer トークンが必要）
function Conv($token, $viewer, $with) {
  $r = Invoke-RestMethod -Uri "$BaseUrl/api/conversation?with=$with" `
    -Headers @{ Authorization = "Bearer $token" }
  $tag = if ($r.cached) { '[cache]' } else { '[fresh]' }
  Write-Host "conversation ($viewer<->$with) $tag :" -ForegroundColor Yellow
  $r.messages | ForEach-Object { "  $($_.from): $($_.text)" } | Write-Host
}

$alice = Onboard 'alice@example.com' 'alice' 'pass-alice'
$bob   = Onboard 'bob@example.com'   'bob'   'pass-bob'
$carol = Onboard 'carol@example.com' 'carol' 'pass-carol'

Send $alice 'alice' 'bob' 'やあ bob！'
Send $bob   'bob' 'alice' 'やあ alice、元気？'
Send $alice 'alice' 'carol' 'carol にも送ってみる'

Conv $alice 'alice' 'bob'
Conv $bob   'bob' 'alice'
Conv $alice 'alice' 'carol'

Write-Host ""
Write-Host "ブラウザで http://localhost:3000 を開き、alice/bob で陳腐化を体験してください。" -ForegroundColor Cyan
