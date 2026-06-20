# tag vs digest（内容ハッシュ＝不変）を「同じタグの上書き」で体感する実験。
#   1. <repo>:v1 を VERSION=v1 でビルド → digest A を記録
#   2. <repo>:v1 を VERSION=v1-edited で再ビルド（タグは同じ・中身だけ違う）→ digest B
#   3. タグ v1 は B を指すように動くが、A は digest 指定なら今も pull できる（不変）
# 「タグは動く参照・digest は不変の指し先」を、自分の手で再現する。
. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$acr = Get-AcrName -ResourceGroup $cfg.ResourceGroup
$repo = $cfg.Repository
$appPath = Join-Path $PSScriptRoot '..\app'

function Get-V1Digest {
    # `tags &&` で tags が null（タグ無しの dangling マニフェスト）を先に弾く。
    # これが無いと contains(null,...) で JMESPath エラーになる。
    az acr manifest list-metadata --registry $acr --name $repo `
        --query "[?tags && contains(tags, 'v1')].digest | [0]" -o tsv
}

Write-Host "== 1) ${repo}:v1 (VERSION=v1) をビルド ==" -ForegroundColor Cyan
az acr build --registry $acr --image "${repo}:v1" --build-arg "VERSION=v1" $appPath | Out-Null
$digestA = Get-V1Digest
Write-Host "digest A (タグ v1 の現在の指し先): $digestA" -ForegroundColor Yellow

Write-Host "`n== 2) 同じタグ ${repo}:v1 を中身だけ変えて再ビルド (VERSION=v1-edited) ==" -ForegroundColor Cyan
az acr build --registry $acr --image "${repo}:v1" --build-arg "VERSION=v1-edited" $appPath | Out-Null
$digestB = Get-V1Digest
Write-Host "digest B (タグ v1 の新しい指し先): $digestB" -ForegroundColor Yellow

Write-Host "`n== 結果 ==" -ForegroundColor Cyan
if ($digestA -ne $digestB) {
    Write-Host "タグは同じ 'v1' のまま、digest が $digestA → $digestB に変わりました。" -ForegroundColor Green
    Write-Host "=> tag は『動く参照』。再現性が要るデプロイは digest 指定 (${repo}@<digest>) が安全。" -ForegroundColor Green
} else {
    Write-Host "digest が変わりませんでした（中身が同一＝レイヤキャッシュ）。VERSION を変えて再実行してください。" -ForegroundColor Red
}

Write-Host "`n現在のマニフェスト一覧:" -ForegroundColor Cyan
az acr manifest list-metadata --registry $acr --name $repo `
    --query "[].{digest:digest, tags:tags, created:createdTime}" -o table
