# Kustomize overlay を ACR を差し込んでから apply / diff する。
#
# 本章の肝: __ACR_LOGIN_SERVER__ の文字列 sed をやめ、`kustomize edit set image` で
# Kustomize に image を「構造的に」差し替えさせる。ACR は simple のデプロイ出力から
# 動的に取得するので、リポジトリにはプレースホルダ (PLACEHOLDER_ACR) だけを残し、
# デプロイ時に実 ACR を注入 → 直後に元へ戻す (作業ツリーを汚さない)。
param(
    [ValidateSet('apply', 'diff')][string]$Action = 'apply',
    [ValidateSet('dev', 'prod')][string]$Env = 'dev',
    [string]$ResourceGroup = 'rg-aks-demo',
    [string]$DeploymentName = 'main'
)
. "$PSScriptRoot/lib.ps1"

$root = (Get-Location).Path
$acr = (Get-DeployOutputs -ResourceGroup $ResourceGroup -DeploymentName $DeploymentName).AcrLoginServer
$dir = Join-Path $root "kustomize/overlays/$Env"
$kfile = Join-Path $dir 'kustomization.yaml'

# 差し込み前の内容を控えておき、最後に必ず戻す (placeholder のまま git に残すため)。
$backup = Get-Content $kfile -Raw
try {
    Set-Location $dir
    # images transformer の newName/newTag を実 ACR・タグに書き換える。
    kustomize edit set image "app-api=$acr/hk/api:v1" "app-front=$acr/hk/front:v1"
    Set-Location $root

    if ($Action -eq 'apply') {
        kubectl apply -k $dir
    }
    else {
        # クラスタ実体と overlay の差分。差分があると exit 1 になるが学習目的では気にしない。
        kubectl diff -k $dir
    }
}
finally {
    Set-Location $root
    # 注入した実 ACR を消し、placeholder に戻す (作業ツリーをクリーンに保つ)。
    Set-Content -Path $kfile -Value $backup -NoNewline
}
