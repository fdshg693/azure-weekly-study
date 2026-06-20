#Requires -Version 7
# consent.ps1 の逆：中間 API(A) → 下流 API(B) の委任許可（管理者同意）を取り消す。
# これを実行すると OBO 交換が AADSTS65001（要同意）で失敗するようになり、/api/chain-obo が 502 を返す。
#   → 「中間層の委任同意」が OBO の前提であることを、出し入れして体感するためのスクリプト。
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"
$e = Read-DotEnv

$aSp = az ad sp show --id $e.API_A_CLIENT_ID | ConvertFrom-Json
$bSp = az ad sp show --id $e.API_B_CLIENT_ID | ConvertFrom-Json

# A の SP に紐づく委任同意を一覧し、B 宛のものをクライアント側で探す（consent.ps1 と同じ流儀）。
$grants = az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$($aSp.id)/oauth2PermissionGrants" | ConvertFrom-Json
$target = $grants.value | Where-Object { $_.resourceId -eq $bSp.id }

if (-not $target) {
    Write-Host 'A→B の委任許可は見つかりませんでした（既に取り消し済み）。' -ForegroundColor Yellow
    return
}

foreach ($grant in $target) {
    az rest --method DELETE --url "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($grant.id)" | Out-Null
}
Write-Host '中間 API(A) → 下流 API(B) の委任許可を取り消しました。' -ForegroundColor Green
Write-Host 'SPA で /api/chain-obo を押すと OBO 交換が AADSTS65001 で失敗し、502 が返ります（task consent で復活）。' -ForegroundColor Yellow
