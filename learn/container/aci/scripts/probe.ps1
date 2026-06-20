# web の FQDN に HTTP で当てて、ACR から pull したページが配信されているかを確かめる。
# (registry の app は build version をページに焼いているので、それが見えれば pull→配信 成功)。
. "$PSScriptRoot\_lib.ps1"

$fqdn = Get-AciOutput -Name 'fqdn'
$url = "http://$fqdn"
Write-Host "GET $url" -ForegroundColor Cyan

try {
    $res = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20
    Write-Host "HTTP $($res.StatusCode)" -ForegroundColor Green
    Write-Host "---- 本文 ----" -ForegroundColor DarkGray
    Write-Host $res.Content
}
catch {
    Write-Host "到達できませんでした: $_" -ForegroundColor Red
    Write-Host "コンテナがまだ起動中か、pull に失敗している可能性。task show でイベントを確認してください。" -ForegroundColor Yellow
}
