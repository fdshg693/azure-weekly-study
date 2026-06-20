#Requires -Version 7
# 中間 API(A) が下流 API(B) を「ユーザーの代理」で呼ぶ委任許可に、テナント全体の管理者同意を与える。
#
# OBO 交換は「A が、サインインしたユーザーの代理で B を呼ぶ」ものなので、A→B の委任許可への同意が前提になる。
#   - client-credentials-daemon の grant は「アプリ許可（roles）の管理者同意」＝ appRoleAssignment だった。
#   - こちらは「委任許可（scp）の管理者同意」＝ oauth2PermissionGrant。委任 vs アプリ許可で同意の置き場所が違う。
# Graph: oauth2PermissionGrants に { clientId=A の SP, consentType=AllPrincipals, resourceId=B の SP, scope='access_as_user' } を POST。
#   consentType=AllPrincipals ＝ テナントの全ユーザーに効く管理者同意（Principal なら個人単位）。
# ※ 管理者同意の付与には管理者権限が要る。
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"
$e = Read-DotEnv

$aSp = az ad sp show --id $e.API_A_CLIENT_ID | ConvertFrom-Json  # 同意の主体（client＝B を呼ぶ側）
$bSp = az ad sp show --id $e.API_B_CLIENT_ID | ConvertFrom-Json  # 同意の対象（resource＝呼ばれる側）

# A の SP に紐づく委任同意を一覧し、B 宛のものをクライアント側で探す（OData $filter を URL に書かない素直な方法。sibling と同じ流儀）。
$grants = az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$($aSp.id)/oauth2PermissionGrants" | ConvertFrom-Json
$existing = $grants.value | Where-Object { $_.resourceId -eq $bSp.id }

if ($existing) {
    Write-Host 'A→B の委任許可は既に存在します。scope を access_as_user に揃えます。' -ForegroundColor Yellow
    $body = @{ scope = 'access_as_user' } | ConvertTo-Json
    $tmp = New-TemporaryFile; Set-Content -Path $tmp -Encoding utf8 -Value $body
    az rest --method PATCH --url "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($existing[0].id)" --headers 'Content-Type=application/json' --body "@$tmp" | Out-Null
    Remove-Item $tmp
} else {
    $body = @{
        clientId    = $aSp.id            # 代理で呼ぶ側＝中間 API(A) の SP
        consentType = 'AllPrincipals'    # テナント全体への管理者同意
        resourceId  = $bSp.id            # 呼ばれる側＝下流 API(B) の SP
        scope       = 'access_as_user'   # 与える委任スコープ
    } | ConvertTo-Json
    $tmp = New-TemporaryFile; Set-Content -Path $tmp -Encoding utf8 -Value $body
    az rest --method POST --url 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' --headers 'Content-Type=application/json' --body "@$tmp" | Out-Null
    Remove-Item $tmp
}

Write-Host "中間 API(A) → 下流 API(B) の委任許可 'access_as_user' に管理者同意を与えました。" -ForegroundColor Green
Write-Host 'SPA でボタンを押し直すと /api/chain-obo が OBO 交換に成功し、200 で B の応答が返ります。' -ForegroundColor Yellow
