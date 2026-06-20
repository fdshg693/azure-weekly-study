#Requires -Version 7
# .env から src/config.js を生成する（SPA に tenantId / spaClientId / apiScope / apiBaseUrl / redirectUri を渡す）。
# ★ SPA が知るのは「中間 API(A)」だけ：apiScope は A のスコープ、apiBaseUrl は A の URL。
#   下流 API(B) は SPA からは見えない（B を呼ぶのは A の責務＝OBO）。多段の各段は「次の段」だけ知る、を構成にも反映する。
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"
$e = Read-DotEnv

$scope = "api://$($e.API_A_CLIENT_ID)/access_as_user"
$out = "export const APP_CONFIG = { tenantId: '$($e.TENANT_ID)', spaClientId: '$($e.SPA_CLIENT_ID)', apiScope: '$scope', apiBaseUrl: '$($e.API_A_BASE_URL)', redirectUri: '$($e.REDIRECT_URI)' };"

$dest = Join-Path $PSScriptRoot '..\src\config.js'
$out | Set-Content -Encoding utf8 $dest
Write-Host 'src/config.js を生成しました。' -ForegroundColor Green
