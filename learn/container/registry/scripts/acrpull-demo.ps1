# AcrPull の因果（認可で pull の可否が変わる）を「ローカルから」段階的に観測する実験。要 Docker。
#
# なぜ SP を使うのか:
#   消費者 UAMI（マネージド ID）は Azure リソースの中からしか使えない（IMDS 経由でトークンを取る）。
#   手元のラップトップから UAMI に成り代わって pull はできないので、「AcrPull だけ持つ
#   サービスプリンシパル(SP)」を“非特権 ID の代役”にして因果を再現する。
#   （UAMI を主語にした正式な pull 失敗の体感は Step 2 の aci で行う。）
#
# 段階実行（-Action で切り替え。各ステップは独立に何度でも叩ける）:
#   setup   : テスト用 SP を作成し AcrPull を付与 → 資格情報を .acrpull-demo.json に保存
#   pull    : 保存した SP で docker login → pull を 1 回試す（★ロールは一切触らない＝何度でも再試行可）
#   revoke  : SP から AcrPull を外す（ロールだけ操作）
#   grant   : SP に AcrPull を付け直す（ロールだけ操作）
#   cleanup : SP を削除し state ファイルを消す
#
# 使い方の流れ:
#   setup → pull(成功) → revoke → pull を数回(反映待ちで 403 に変わる) → grant → pull(また成功) → cleanup
# 肝: 反映が遅くても再 pull はロールを触らないので、待って pull を再実行すれば 403 を観測できる。
# おまけ: docker login(認証) は通るのに pull(認可) が落ちる＝認証と認可は別、も体感できる。
param(
    [Parameter(Mandatory)][ValidateSet('setup', 'pull', 'revoke', 'grant', 'cleanup')]
    [string]$Action,
    [string]$Tag = 'v1',
    [string]$SpName = 'sp-acrpull-test'
)

. "$PSScriptRoot\_lib.ps1"

$statePath = Join-Path $PSScriptRoot '..\.acrpull-demo.json'

function Save-State { param($State) $State | ConvertTo-Json | Set-Content -Path $statePath -Encoding utf8 }
function Load-State {
    if (-not (Test-Path $statePath)) {
        throw "state がありません（$statePath）。先に `task acrpull-setup` を実行してください。"
    }
    return Get-Content $statePath -Raw | ConvertFrom-Json
}
function Assert-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "docker が見つかりません。この実験はローカル Docker が要ります。"
    }
}

switch ($Action) {

    'setup' {
        Assert-Docker
        if (Test-Path $statePath) {
            throw "既に state があります（前回の SP が残存）。先に `task acrpull-cleanup` を実行してください。"
        }
        $cfg = Get-Config
        $acr = Get-AcrName -ResourceGroup $cfg.ResourceGroup
        $loginServer = Get-Output -ResourceGroup $cfg.ResourceGroup -Name 'acrLoginServer'
        $repo = $cfg.Repository
        $acrId = az acr show --name $acr --resource-group $cfg.ResourceGroup --query id -o tsv

        Write-Host "== AcrPull だけ持つテスト用 SP を作成（ロール付与込み・scope=ACR） ==" -ForegroundColor Cyan
        $sp = az ad sp create-for-rbac --name $SpName --role AcrPull --scopes $acrId | ConvertFrom-Json

        Save-State ([pscustomobject]@{
            SpName      = $SpName
            AppId       = $sp.appId
            Password    = $sp.password   # ★テスト用 SP の秘密。state ファイルは .gitignore 済み・cleanup で削除。
            AcrId       = $acrId
            LoginServer = $loginServer
            Image       = "$loginServer/${repo}:$Tag"
        })
        Write-Host "SP appId=$($sp.appId) を作成し、資格情報を state に保存しました。" -ForegroundColor Green
        Write-Host "次: `task acrpull-pull`（AcrPull があるので成功するはず。反映に少し時間が要る場合あり）" -ForegroundColor Yellow
    }

    'pull' {
        Assert-Docker
        $s = Load-State
        # 毎回 logout→login して“新しいトークン”で評価させる（ACR のアクセストークンは
        # 発行時に RBAC を見るため、古いトークンだとロール変更が反映されない）。
        # ★このステップはロールを一切操作しない＝待って何度でも再実行できる。
        docker logout $s.LoginServer | Out-Null
        Write-Host "docker login（認証）..." -ForegroundColor Cyan
        docker login $s.LoginServer -u $s.AppId -p $s.Password 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "docker login が失敗しました（認証レベルの問題＝想定外）。" -ForegroundColor Red
            break
        }
        Write-Host "docker pull $($s.Image)（認可＝AcrPull の有無で変わる）..." -ForegroundColor Cyan
        docker pull $s.Image 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Write-Host "=> pull 成功: いまこの SP は AcrPull を持っている。" -ForegroundColor Green
        } else {
            Write-Host "=> pull 失敗(403): AcrPull が無い状態。" -ForegroundColor Green
            Write-Host "   docker login（認証）は通ったのに pull（認可）だけ落ちた＝認証と認可は別。" -ForegroundColor Green
        }
        Write-Host "(revoke 直後に成功してしまう場合は RBAC 反映待ち。ロールは触らず `task acrpull-pull` を数回叩いて観察)" -ForegroundColor DarkGray
    }

    'revoke' {
        $s = Load-State
        Write-Host "== SP から AcrPull を外す（ロールだけ操作） ==" -ForegroundColor Cyan
        az role assignment delete --assignee $s.AppId --role AcrPull --scope $s.AcrId
        Write-Host "外しました。次: 少し待って `task acrpull-pull` を（何度でも）実行し 403 を観察。" -ForegroundColor Yellow
    }

    'grant' {
        $s = Load-State
        Write-Host "== SP に AcrPull を付け直す（ロールだけ操作） ==" -ForegroundColor Cyan
        az role assignment create --assignee-object-id (az ad sp show --id $s.AppId --query id -o tsv) `
            --assignee-principal-type ServicePrincipal --role AcrPull --scope $s.AcrId | Out-Null
        Write-Host "付け直しました。次: 少し待って `task acrpull-pull` で成功に戻るのを観察。" -ForegroundColor Yellow
    }

    'cleanup' {
        if (Test-Path $statePath) {
            $s = Load-State
            if (Get-Command docker -ErrorAction SilentlyContinue) { docker logout $s.LoginServer | Out-Null }
            Write-Host "== テスト用 SP を削除 ==" -ForegroundColor Cyan
            az ad sp delete --id $s.AppId
            Remove-Item $statePath -Force
            Write-Host "SP と state を削除しました。" -ForegroundColor Green
        } else {
            Write-Host "state がありません。削除するものはありません（既に cleanup 済み）。" -ForegroundColor Yellow
        }
    }
}
