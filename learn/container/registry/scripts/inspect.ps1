# レジストリの中身を覗く: リポジトリ一覧 → タグ → マニフェスト(digest 付き)。
# 「tag は人が読むラベル / digest は内容のハッシュ＝不変の指し先」を目で確かめる。
. "$PSScriptRoot\_lib.ps1"
$cfg = Get-Config
$acr = Get-AcrName -ResourceGroup $cfg.ResourceGroup
$repo = $cfg.Repository

Write-Host "== リポジトリ一覧 ==" -ForegroundColor Cyan
az acr repository list --name $acr -o table

Write-Host "`n== $repo のタグ ==" -ForegroundColor Cyan
az acr repository show-tags --name $acr --repository $repo -o table

Write-Host "`n== $repo のマニフェスト (digest / tag / 作成時刻) ==" -ForegroundColor Cyan
# digest は sha256:...、同じタグを上書きしても digest は内容ごとに別物になる。
az acr manifest list-metadata --registry $acr --name $repo `
    --query "[].{digest:digest, tags:tags, created:createdTime}" -o table

Write-Host "`n== レジストリのヘルスチェック ==" -ForegroundColor Cyan
az acr check-health --name $acr --yes
