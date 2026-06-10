# 各スクリプトから dot-source（. "$PSScriptRoot\_lib.ps1"）して使う共有ヘルパー。
# プロジェクト直下の .env を読み、キー=値 のハッシュテーブルにして返す（justfile 時代と同じ素朴なパーサ）。
function Read-DotEnv {
    param(
        # 既定はこのスクリプト（scripts/）の 1 つ上 ＝ プロジェクト直下の .env。
        [string]$Path = (Join-Path $PSScriptRoot '..\.env')
    )
    if (-not (Test-Path $Path)) {
        throw ".env がありません（$Path）。.env.example をコピーして値を入れてください。"
    }
    $env = @{}
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*[^#].*=') {
            $k, $v = $line -split '=', 2
            $env[$k.Trim()] = $v.Trim()
        }
    }
    return $env
}
