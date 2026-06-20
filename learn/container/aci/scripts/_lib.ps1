# 各スクリプトから dot-source (. "$PSScriptRoot\_lib.ps1") して使う共有ヘルパー。
# registry プロジェクト (Step 1) と同じ素朴な作り。ACI は registry の出力
# (ACR / 消費者 UAMI) を参照するので、その読み出しヘルパーをここに集約する。

# プロジェクト直下の .env を読み、キー=値 のハッシュテーブルにして返す。
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

function Get-Setting {
    param([hashtable]$Env, [string]$Key, [string]$Default)
    if ($Env.ContainsKey($Key) -and $Env[$Key]) { return $Env[$Key] }
    return $Default
}

# よく使う設定をまとめて返す。RegistryRG が Step 1 のデプロイ先 (ACR/UAMI の在処)。
function Get-Config {
    $e = Read-DotEnv
    return [pscustomobject]@{
        ResourceGroup = Get-Setting $e 'RG'          'rg-container-aci'
        Location      = Get-Setting $e 'LOCATION'    'japaneast'
        Prefix        = Get-Setting $e 'PREFIX'      'aci'
        # Step 1 (registry) をデプロイした RG。ここから ACR / UAMI を引いてくる。
        RegistryRG    = Get-Setting $e 'REGISTRY_RG' 'rg-container-registry'
        # registry に上げたイメージ (repository:tag)。registry 既定と合わせる。
        Repository    = Get-Setting $e 'REPO'        'web'
        Tag           = Get-Setting $e 'TAG'         'v1'
    }
}

# 任意デプロイの出力を 1 つ取り出す。
function Get-DeploymentOutput {
    param([string]$ResourceGroup, [string]$Deployment, [string]$Name)
    $val = az deployment group show --resource-group $ResourceGroup --name $Deployment `
        --query "properties.outputs.$Name.value" -o tsv
    if (-not $val) {
        throw "デプロイ '$Deployment' の出力 '$Name' が取得できません (RG=$ResourceGroup)。"
    }
    return $val.Trim()
}

# Step 1 (registry) のデプロイ出力 (ACR / 消費者 UAMI) をまとめて取得する。
# これらを ACI に渡して「同じ ACR から keyless pull」を実現する。
function Get-RegistryOutputs {
    $cfg = Get-Config
    $rg = $cfg.RegistryRG
    try {
        return [pscustomobject]@{
            AcrName         = Get-DeploymentOutput -ResourceGroup $rg -Deployment 'main' -Name 'acrName'
            AcrLoginServer  = Get-DeploymentOutput -ResourceGroup $rg -Deployment 'main' -Name 'acrLoginServer'
            UamiResourceId  = Get-DeploymentOutput -ResourceGroup $rg -Deployment 'main' -Name 'uamiResourceId'
            UamiPrincipalId = Get-DeploymentOutput -ResourceGroup $rg -Deployment 'main' -Name 'uamiPrincipalId'
        }
    }
    catch {
        throw "registry (Step 1) の出力が読めません。先に learn/container/registry で `task up` を実行しましたか？ (REGISTRY_RG=$rg)`n$_"
    }
}

# ACI 側 (このプロジェクト) の main デプロイ出力を取り出す。
function Get-AciOutput {
    param([string]$Name)
    $cfg = Get-Config
    return Get-DeploymentOutput -ResourceGroup $cfg.ResourceGroup -Deployment 'main' -Name $Name
}
