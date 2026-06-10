#Requires -Version 7
# .env から src/config.js を生成する（SPA に tenantId / spaClientId / apiScope / apiBaseUrl / redirectUri を渡す）。
# apiScope は API_CLIENT_ID から組み立てる（api://<API_CLIENT_ID>/access_as_user）。
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"
$e = Read-DotEnv

$scope = "api://$($e.API_CLIENT_ID)/access_as_user"
$out = "export const APP_CONFIG = { tenantId: '$($e.TENANT_ID)', spaClientId: '$($e.SPA_CLIENT_ID)', apiScope: '$scope', apiBaseUrl: '$($e.API_BASE_URL)', redirectUri: '$($e.REDIRECT_URI)' };"

$dest = Join-Path $PSScriptRoot '..\src\config.js'
$out | Set-Content -Encoding utf8 $dest
Write-Host 'src/config.js を生成しました。' -ForegroundColor Green
