<#
.SYNOPSIS
  Azure Automation の PowerShell runbook。Automation Account の
  「システム割り当てマネージド ID」として認証し、対象 VM を Start / Stop(deallocate) する。

.DESCRIPTION
  このトピック (automate) の 2 つめのプロジェクト。simple (Container Apps Job) が
  「自作コンテナを起動して終了する」モデルだったのに対し、ここでは
  「Azure が用意したマネージド実行環境で runbook(スクリプト) を走らせ、
   Automation Account 自身の ID で Azure リソースを操作する」モデルを体験する。

  肝は次の 3 点:
    1. Connect-AzAccount -Identity … コンテナイメージも鍵も無しに、
       Automation Account の system-assigned マネージド ID として Azure にサインインする。
    2. ロール(RBAC) で「できること」が決まる … 認証(誰として動くか)と
       認可(何をしてよいか)は別。Reader だけだと電源状態は読めても Start/Stop は 403。
    3. Automation 変数(共有アセット) … スケジュール実行のように引数が無いときは、
       コードの外に置いた変数から設定を読む(コードを書き換えずに挙動を変えられる)。

.NOTES
  - 実行ランタイムは Windows PowerShell 5.1 (runbookType=PowerShell)。
  - Az モジュール(Az.Accounts / Az.Compute) は新しい Automation Account に既定で入っている。
    もし "コマンドが見つからない" 系のエラーが出たら、Automation Account の [モジュール] で
    Az.Accounts と Az.Compute をインポートする (README のトラブルシュート参照)。
  - Get-AutomationVariable は Automation のサンドボックス内でのみ使える内部コマンドレット
    (ローカルの pwsh では動かない)。
#>

param(
    # Start / Stop / Status。空のときは Automation 変数 DefaultAction を使う(スケジュール実行向け)。
    [string] $Action = '',

    # 操作対象 VM。空のときは Automation 変数 TargetVMName / TargetVMResourceGroup を使う。
    [string] $VMName = '',
    [string] $VMResourceGroup = '',

    # true にすると最後にわざと例外を投げ、ジョブを Failed にする(失敗とエラーストリームの観察用)。
    [bool] $FailJob = $false
)

$ErrorActionPreference = 'Stop'

function Log([string] $message) {
    # 行頭に UTC タイムスタンプを付けて出力(= ジョブの Output ストリームへ)。
    Write-Output ('[{0}] {1}' -f [DateTime]::UtcNow.ToString('o'), $message)
}

Log 'runbook start'

# --------------------------------------------------------------------------
# 1. 共有アセット(Automation 変数)で引数を補う
#    手動起動時は --parameters で渡せるが、スケジュール実行は引数が無い。
#    そのときはコードの外に置いた変数から読む = 設定とコードの分離。
# --------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Action))          { $Action = Get-AutomationVariable -Name 'DefaultAction' }
if ([string]::IsNullOrWhiteSpace($VMName))           { $VMName = Get-AutomationVariable -Name 'TargetVMName' }
if ([string]::IsNullOrWhiteSpace($VMResourceGroup))  { $VMResourceGroup = Get-AutomationVariable -Name 'TargetVMResourceGroup' }

Log ("inputs: Action='{0}' VMName='{1}' VMResourceGroup='{2}'" -f $Action, $VMName, $VMResourceGroup)

# --------------------------------------------------------------------------
# 2. 認証: Automation Account の system-assigned マネージド ID としてサインイン
#    コンテナも資格情報も無い。アカウントに紐づいた ID で Azure に入る。
# --------------------------------------------------------------------------
Log 'connecting with the system-assigned managed identity...'
Connect-AzAccount -Identity | Out-Null
$ctx = Get-AzContext
Log ("connected as: {0} (subscription {1})" -f $ctx.Account.Id, $ctx.Subscription.Id)

# --------------------------------------------------------------------------
# 3. 電源状態を読む(Reader 権限で足りる)
# --------------------------------------------------------------------------
$vm = Get-AzVM -ResourceGroupName $VMResourceGroup -Name $VMName -Status
$power = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' } | Select-Object -First 1).Code
Log "current power state: $power"

# --------------------------------------------------------------------------
# 4. 操作する(Start/Stop には Virtual Machine Contributor 権限が必要)
#    ここで 403 が出るなら「認証は成功(ID は分かる)、でも認可が無い」状態。
#    = just revoke-vmcontrib でロールを外したときの挙動。
# --------------------------------------------------------------------------
switch ($Action) {
    'Start' {
        Log 'starting VM...'
        Start-AzVM -ResourceGroupName $VMResourceGroup -Name $VMName | Out-Null
    }
    'Stop' {
        # -Force で確認を出さず deallocate(課金停止状態) にする。
        Log 'stopping (deallocating) VM...'
        Stop-AzVM -ResourceGroupName $VMResourceGroup -Name $VMName -Force | Out-Null
    }
    'Status' {
        Log 'status only — no action taken'
    }
    default {
        throw "unknown Action '$Action' (expected Start / Stop / Status)"
    }
}

# 操作後の状態を読み直して、変化を出力に残す。
if ($Action -in @('Start', 'Stop')) {
    $vmAfter = Get-AzVM -ResourceGroupName $VMResourceGroup -Name $VMName -Status
    $powerAfter = ($vmAfter.Statuses | Where-Object { $_.Code -like 'PowerState/*' } | Select-Object -First 1).Code
    Log "new power state: $powerAfter"
}

# --------------------------------------------------------------------------
# 5. 失敗デモ: わざと例外を投げてジョブを Failed にする
# --------------------------------------------------------------------------
if ($FailJob) {
    throw 'FailJob=true: failing on purpose (demonstrates Failed status + Error stream)'
}

Log 'runbook done'
