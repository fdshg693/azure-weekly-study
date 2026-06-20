# dev と prod の「レンダリング結果」を並べて差分表示する (クラスタには触れない)。
# 同じベース/チャートから overlay/values の差分だけで何が変わるかを可視化する、
# この章の中心的な観察。Tool で Kustomize 版 / Helm 版を切り替える。
param(
    [ValidateSet('kustomize', 'helm')][string]$Tool = 'kustomize'
)

$devOut = Join-Path $env:TEMP "hk-$Tool-dev.yaml"
$prodOut = Join-Path $env:TEMP "hk-$Tool-prod.yaml"

if ($Tool -eq 'kustomize') {
    kubectl kustomize kustomize/overlays/dev  | Set-Content $devOut
    kubectl kustomize kustomize/overlays/prod | Set-Content $prodOut
}
else {
    helm template app helm/app --values helm/app/values-dev.yaml  | Set-Content $devOut
    helm template app helm/app --values helm/app/values-prod.yaml | Set-Content $prodOut
}

# git の差分ビューアを流用 (リポジトリ外でも --no-index で使える)。差分があると exit 1。
git --no-pager diff --no-index -- $devOut $prodOut
