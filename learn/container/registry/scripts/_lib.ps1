# 各スクリプトから dot-source（. "$PSScriptRoot\_lib.ps1"）して使う共有ヘルパー。
# sibling プロジェクト（auth/*）と同じ素朴な作りにしてある。

# プロジェクト直下の .env を読み、キー=値 のハッシュテーブルにして返す。
# このプロジェクトに秘密は無いが、RG / LOCATION / PREFIX を .env で差し替えられるようにしている。
function Read-DotEnv {
    param(
        [string]$Path = (Join-Path $PSScriptRoot '..\.env')
    )
    $envVars = @{}
    if (Test-Path $Path) {
        foreach ($line in Get-Content $Path) {
            if ($line -match '^\s*[^#].*=') {
                $k, $v = $line -split '=', 2
                $envVars[$k.Trim()] = $v.Trim()
            }
        }
    }
    return $envVars
}

# .env の値（無ければ既定値）を返す小さなヘルパー。
function Get-Setting {
    param([hashtable]$Env, [string]$Key, [string]$Default)
    if ($Env.ContainsKey($Key) -and $Env[$Key]) { return $Env[$Key] }
    return $Default
}

# よく使う設定をまとめて返す（RG / LOCATION / PREFIX / REPOSITORY）。
function Get-Config {
    $e = Read-DotEnv
    return [pscustomobject]@{
        ResourceGroup = Get-Setting $e 'RG'       'rg-container-registry'
        Location      = Get-Setting $e 'LOCATION' 'japaneast'
        Prefix        = Get-Setting $e 'PREFIX'   'reg'
        # レジストリ内のイメージ名（リポジトリ名）。レジストリ内で一意なら何でもよい。
        Repository    = Get-Setting $e 'REPO'     'web'
    }
}

# デプロイ出力から 1 つの値を取り出す（main デプロイの outputs.<name>.value）。
function Get-Output {
    param([string]$ResourceGroup, [string]$Name)
    $val = az deployment group show --resource-group $ResourceGroup --name main `
        --query "properties.outputs.$Name.value" -o tsv
    if (-not $val) {
        throw "デプロイ出力 '$Name' が取得できません。先に `task deploy` を実行しましたか？ (RG=$ResourceGroup)"
    }
    return $val.Trim()
}

# ACR 名を取得する近道。
function Get-AcrName {
    param([string]$ResourceGroup)
    return Get-Output -ResourceGroup $ResourceGroup -Name 'acrName'
}
