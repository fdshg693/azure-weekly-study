#Requires -Version 7
# 後片付け：アプリ登録を削除する（.env の CLIENT_ID を使用）。
# クライアントシークレットやサービス プリンシパルも、アプリ登録の削除に伴って消える。
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"
$e = Read-DotEnv

if ($e.CLIENT_ID) {
    az ad app delete --id $e.CLIENT_ID
    Write-Host 'アプリ登録を削除しました。' -ForegroundColor Green
} else {
    Write-Host '.env に CLIENT_ID がありません。' -ForegroundColor Yellow
}
