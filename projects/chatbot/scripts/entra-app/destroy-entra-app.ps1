<#
.SYNOPSIS
  Entra ID App Registration を削除して後片付けする。

.DESCRIPTION
  setup-entra-app.ps1 で作成した App Registration（とサービスプリンシパル）を削除する。
  あわせてローカルの auth.auto.tfvars も削除する。
  既定では確認プロンプトを出す。-Force で確認をスキップ。

.NOTES
  App Registration を消すと紐づくサービスプリンシパル・シークレットも一緒に消える。
#>
param(
  [string] $DisplayName = "chatbot-graph-demo",
  [string] $TfvarsPath  = "auth.auto.tfvars",
  [switch] $Force
)

. "$PSScriptRoot/../_common.ps1"

$app = Find-EntraApp -DisplayName $DisplayName
if (-not $app) {
  Write-Host "App Registration '$DisplayName' は見つかりませんでした（既に削除済み？）。" -ForegroundColor Yellow
}
else {
  Write-Host "削除対象: $($app.displayName)  appId=$($app.appId)" -ForegroundColor Yellow
  if (-not $Force) {
    $answer = Read-Host "本当に削除しますか？ (y/N)"
    if ($answer -ne "y") {
      Write-Host "中止しました。"
      exit 0
    }
  }
  az ad app delete --id $app.appId | Out-Null
  Write-Host "✅ App Registration を削除しました。" -ForegroundColor Green
}

if (Test-Path $TfvarsPath) {
  Remove-Item $TfvarsPath -Force
  Write-Host "✅ $TfvarsPath を削除しました。" -ForegroundColor Green
  Write-Host "   App Settings から値を消すには 'just up'（entra_* が空に戻る）を実行してください。"
}
