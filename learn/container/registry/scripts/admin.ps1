# admin user（共有パスワード）の有効/無効を出し入れし、認証方式の違いを体感する。
#   有効: `az acr credential show` で username/password が出る＝誰でも使える共有秘密。
#   無効（既定・推奨）: credential show は失敗し、認証は Entra トークン + RBAC のみ。
# 「キーレス(Entra+RBAC) を第一選択にし、admin user はアンチパターン」を手で確かめる。
param(
    [Parameter(Mandatory)][ValidateSet('on', 'off')][string]$Action
)

. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$acr = Get-AcrName -ResourceGroup $cfg.ResourceGroup

$enabled = ($Action -eq 'on')
Write-Host "admin user を $Action にします: $acr" -ForegroundColor Cyan
az acr update --name $acr --admin-enabled $enabled | Out-Null

Write-Host "`n== az acr credential show の結果 ==" -ForegroundColor Cyan
if ($enabled) {
    Write-Host "（有効化したので共有の username/password が見えるはず＝アンチパターン）" -ForegroundColor Yellow
    az acr credential show --name $acr -o table
} else {
    Write-Host "（無効化したので credential は取得できない＝Entra トークン認証のみ）" -ForegroundColor Yellow
    # 無効時はエラーになるのが正しい挙動。失敗しても task を止めない。
    az acr credential show --name $acr -o table 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "想定どおり credential show は失敗しました（admin user 無効＝共有パスワード無し）。" -ForegroundColor Green
    }
}
