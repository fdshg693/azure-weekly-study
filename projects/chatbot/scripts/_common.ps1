# ============================================================================
# Entra ID 関連スクリプトの共通ヘルパー
# ============================================================================
# 各スクリプトの先頭で `. "$PSScriptRoot/../_common.ps1"` として読み込む（scripts/ 直下に配置）。
# az CLI を叩く小さなユーティリティと、Microsoft Graph の well-known ID を定義する。

$ErrorActionPreference = "Stop"

# ----------------------------------------------------------------------------
# Microsoft Graph の固定 ID（テナントに依らず全世界共通）
# ----------------------------------------------------------------------------
# Graph アプリ（リソース）の appId
$script:GRAPH_APP_ID = "00000003-0000-0000-c000-000000000000"
# Graph の "User.Read" デリゲート権限（Scope）の ID。/me 呼び出しに必要。
$script:GRAPH_USER_READ_SCOPE_ID = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"

# ----------------------------------------------------------------------------
# az CLI にログイン済みかを確認し、テナント ID を返す
# ----------------------------------------------------------------------------
function Get-TenantId {
  $tenant = az account show --query tenantId -o tsv 2>$null
  if (-not $tenant) {
    throw "az にログインしていません。先に 'az login' を実行してください。"
  }
  return $tenant.Trim()
}

# ----------------------------------------------------------------------------
# 表示名から App Registration を 1 件取得する（無ければ $null）
# 戻り値は az ad app show 相当のオブジェクト
# ----------------------------------------------------------------------------
function Find-EntraApp {
  param([Parameter(Mandatory)] [string] $DisplayName)

  $appId = az ad app list --display-name $DisplayName --query "[0].appId" -o tsv 2>$null
  if (-not $appId) { return $null }
  return az ad app show --id $appId.Trim() | ConvertFrom-Json
}

# ----------------------------------------------------------------------------
# Microsoft Graph に PATCH リクエストを送る（複雑なオブジェクトの更新用）
# az ad app update では扱いにくい web.logoutUrl / api.* を一括更新するために使う。
# $Body は PowerShell のハッシュテーブル。一時 JSON ファイル経由で渡すことで
# PowerShell -> az 間のクォート地獄を避ける。
# ----------------------------------------------------------------------------
function Invoke-GraphPatch {
  param(
    [Parameter(Mandatory)] [string]    $ObjectId,
    [Parameter(Mandatory)] [hashtable] $Body
  )

  $tmp = Join-Path $env:TEMP ("entra-patch-" + [guid]::NewGuid().ToString() + ".json")
  try {
    $Body | ConvertTo-Json -Depth 20 | Set-Content -Path $tmp -Encoding utf8
    az rest --method PATCH `
      --uri "https://graph.microsoft.com/v1.0/applications/$ObjectId" `
      --headers "Content-Type=application/json" `
      --body "@$tmp" | Out-Null
  }
  finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
  }
}
