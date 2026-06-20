<#
.SYNOPSIS
  ローカル開発者（az にサインイン中の自分）に対する Azure OpenAI の
  データ操作ロール「Cognitive Services OpenAI User」を付与/確認/剥奪する。

.DESCRIPTION
  ローカルから tools-demo.js や `just dev` で Azure OpenAI を呼ぶには、
  自分の Entra プリンシパルに「Cognitive Services OpenAI User」ロールが
  必要（無いと chat/completions が 401 になる）。
  このスクリプトはそのロールを 1 本で管理し、CLAUDE.md の方針どおり
  「権限を操作 → API のレスポンスが変わる」体験をしやすくする。

    -Action grant   … 自分にロールを付与（既にあれば az 側が冪等に扱う）
    -Action show    … 自分の現在の割り当て状況を表示（読み取り専用）
    -Action revoke  … 自分からロールを剥奪（401 に戻る様子を体験する用）

  対象の Azure OpenAI アカウント名・リソースグループ名は terraform output
  から取得する（grant-self と同じ前提＝先に `just apply` 済みであること）。

.NOTES
  Reader 系を除き grant/revoke は書き込み操作。明示的に叩いたときのみ実行される。
#>
param(
  [ValidateSet("grant", "show", "revoke")]
  [string] $Action = "grant"
)

$ErrorActionPreference = "Stop"

# このロールが chat/completions などの「データ操作」を許可する。
$RoleName = "Cognitive Services OpenAI User"

# ----------------------------------------------------------------------------
# 前提情報の解決（サインインユーザー / アカウント名 / RG / サブスク / スコープ）
# ----------------------------------------------------------------------------
$me = az ad signed-in-user show --query id -o tsv 2>$null
if (-not $me) {
  throw "az にログインしていません。先に 'az login' を実行してください。"
}
$me = $me.Trim()

# terraform 管理下の Azure OpenAI アカウント名 / リソースグループ名を取得
$aoai = (terraform output -raw openai_account_name 2>$null)
$rg   = (terraform output -raw resource_group_name 2>$null)
if (-not $aoai -or -not $rg) {
  throw "terraform output を取得できません。先に 'just apply' でインフラを作成してください。"
}
$sub = (az account show --query id -o tsv).Trim()

# ロールを割り当てるスコープ（Azure OpenAI アカウント単位）
$scope = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$aoai"

Write-Host "対象ユーザー : $me" -ForegroundColor DarkGray
Write-Host "対象リソース : $aoai (rg=$rg)" -ForegroundColor DarkGray
Write-Host "ロール       : $RoleName" -ForegroundColor DarkGray
Write-Host ""

switch ($Action) {
  "grant" {
    az role assignment create --assignee $me --role $RoleName --scope $scope | Out-Null
    Write-Host "✅ 付与しました。反映に十数秒〜数分かかることがあります。" -ForegroundColor Green
    Write-Host "   確認: just aoai-role-show / 動作: node app/tools-demo.js" -ForegroundColor DarkGray
  }

  "show" {
    # 自分のこのスコープ上の割り当てを一覧（無ければ空）
    $assignments = az role assignment list --assignee $me --scope $scope `
      --query "[].{role:roleDefinitionName, scope:scope}" -o json | ConvertFrom-Json
    $hasRole = $assignments | Where-Object { $_.role -eq $RoleName }
    if ($hasRole) {
      Write-Host "✅ '$RoleName' は付与済みです。" -ForegroundColor Green
    } else {
      Write-Host "⛔ '$RoleName' は未付与です（chat/completions は 401 になります）。" -ForegroundColor Yellow
      Write-Host "   付与: just aoai-grant-self" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "このスコープ上の自分の全ロール割り当て:" -ForegroundColor Cyan
    if ($assignments) {
      $assignments | ForEach-Object { Write-Host "  - $($_.role)" }
    } else {
      Write-Host "  (なし)" -ForegroundColor Yellow
    }
  }

  "revoke" {
    az role assignment delete --assignee $me --role $RoleName --scope $scope | Out-Null
    Write-Host "🗑️  剥奪しました。再付与するまで chat/completions は 401 になります。" -ForegroundColor Yellow
    Write-Host "   体験: node app/tools-demo.js（401 を確認）→ just aoai-grant-self → 再実行" -ForegroundColor DarkGray
  }
}

Write-Host ""
