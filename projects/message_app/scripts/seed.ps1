# 動作確認用シード。BFF(http://localhost:3000) 経由で API を叩き、
# ユーザー作成 → メッセージ送信 → 会話取得まで一通り通す。
# 前提: task local-up / api / functions / bff が起動済み。
param([string]$BaseUrl = "http://localhost:3000")
$ErrorActionPreference = 'Stop'

function Login($name) {
  Invoke-RestMethod -Uri "$BaseUrl/api/login" -Method Post `
    -ContentType 'application/json' -Body (@{ username = $name } | ConvertTo-Json) | Out-Null
  Write-Host "login: $name" -ForegroundColor Green
}

function Send($from, $to, $text) {
  Invoke-RestMethod -Uri "$BaseUrl/api/messages" -Method Post `
    -Headers @{ 'X-User' = $from } -ContentType 'application/json' `
    -Body (@{ to = $to; text = $text } | ConvertTo-Json) | Out-Null
  Write-Host "send: $from -> $to : $text" -ForegroundColor Cyan
}

function Conv($viewer, $with) {
  $r = Invoke-RestMethod -Uri "$BaseUrl/api/conversation?with=$with" -Headers @{ 'X-User' = $viewer }
  $tag = if ($r.cached) { '[cache]' } else { '[fresh]' }
  Write-Host "conversation ($viewer<->$with) $tag :" -ForegroundColor Yellow
  $r.messages | ForEach-Object { "  $($_.from): $($_.text)" } | Write-Host
}

Login 'alice'
Login 'bob'
Login 'carol'

Send 'alice' 'bob' 'やあ bob！'
Send 'bob'   'alice' 'やあ alice、元気？'
Send 'alice' 'carol' 'carol にも送ってみる'

Conv 'alice' 'bob'
Conv 'bob'   'alice'
Conv 'alice' 'carol'

Write-Host ""
Write-Host "ブラウザで http://localhost:3000 を開き、alice/bob で陳腐化を体験してください。" -ForegroundColor Cyan
