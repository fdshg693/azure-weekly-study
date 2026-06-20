# コンテナの標準出力ログを表示する。
#   - web        : nginx のアクセスログ
#   - crasher    : restart 実験の "[crasher] exiting N"
#   - sidecar    : "[sidecar] reached web on localhost:80"
param(
    [string]$Cg = '',          # 既定は web の Container Group
    [string]$Container = ''    # コンテナグループ内の特定コンテナ名 (sidecar 実験で使う)
)

. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$name = if ($Cg) { $Cg } else { "cg-$($cfg.Prefix)-web" }

$cmd = @('container', 'logs', '--resource-group', $cfg.ResourceGroup, '--name', $name)
if ($Container) { $cmd += @('--container-name', $Container) }

az @cmd
