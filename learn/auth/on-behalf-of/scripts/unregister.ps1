#Requires -Version 7
# 後片付け：3 つのアプリ登録を削除する（.env の SPA_CLIENT_ID / API_A_CLIENT_ID / API_B_CLIENT_ID を使用）。
# 委任同意（oauth2PermissionGrant）・SP・シークレットは、アプリ登録を消せば一緒に消える。
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"
$e = Read-DotEnv

foreach ($pair in @(
    @{ name = 'SPA';        id = $e.SPA_CLIENT_ID },
    @{ name = '中間 API(A)'; id = $e.API_A_CLIENT_ID },
    @{ name = '下流 API(B)'; id = $e.API_B_CLIENT_ID }
)) {
    if ($pair.id) {
        az ad app delete --id $pair.id
        Write-Host "$($pair.name) のアプリ登録を削除しました。" -ForegroundColor Green
    }
}
