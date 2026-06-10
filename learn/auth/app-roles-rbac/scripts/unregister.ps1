#Requires -Version 7
# 後片付け：2 つのアプリ登録を削除する（.env の SPA_CLIENT_ID / API_CLIENT_ID を使用）。
# ロールの割り当ては、API のアプリ登録（と SP）を消せば一緒に消える。
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"
$e = Read-DotEnv

if ($e.SPA_CLIENT_ID) {
    az ad app delete --id $e.SPA_CLIENT_ID
    Write-Host 'SPA アプリ登録を削除しました。' -ForegroundColor Green
}
if ($e.API_CLIENT_ID) {
    az ad app delete --id $e.API_CLIENT_ID
    Write-Host 'API アプリ登録を削除しました。' -ForegroundColor Green
}
