#Requires -Version 7
# 後片付け：自前 API とデーモンの 2 つのアプリ登録を削除する（.env の API_CLIENT_ID / CLIENT_ID を使用）。
# クライアントシークレット・サービス プリンシパル・ロール割り当ても、アプリ登録の削除に伴って消える。
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"
$e = Read-DotEnv

if ($e.CLIENT_ID) {
    az ad app delete --id $e.CLIENT_ID
    Write-Host 'デーモンのアプリ登録を削除しました。' -ForegroundColor Green
} else {
    Write-Host '.env に CLIENT_ID がありません。' -ForegroundColor Yellow
}

if ($e.API_CLIENT_ID) {
    az ad app delete --id $e.API_CLIENT_ID
    Write-Host '自前 API のアプリ登録を削除しました。' -ForegroundColor Green
} else {
    Write-Host '.env に API_CLIENT_ID がありません。' -ForegroundColor Yellow
}
