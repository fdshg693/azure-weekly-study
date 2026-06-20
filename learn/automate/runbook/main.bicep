// ============================================================================
// automate/runbook — Azure Automation の runbook が主役のプロジェクト
// ============================================================================
// 「自作コンテナを起動して終了する」(simple = Container Apps Job) に対し、
// 「Azure のマネージド実行環境で runbook を走らせ、Automation Account 自身の
//  マネージド ID で Azure リソース(ここでは VM)を操作する」モデルを学ぶ。
//
// 構成:
//   modules/account.bicep … Automation Account + MI + ロール + 共有変数
//   modules/runbook.bicep … Runbook(空ドラフト) + 任意のスケジュール
//
// デプロイ:
//   az deployment group create -g rg-automate-runbook \
//     --template-file main.bicep --parameters main.bicepparam
//
// 注意: runbook はデプロイ直後は中身が空。`just upload` で本文を発行しないと実行できない。

@description('デプロイ先リージョン')
param location string = resourceGroup().location

@description('リソース名のプレフィックス')
@minLength(1)
@maxLength(12)
param prefix string = 'rbvm'

@description('操作対象 VM 名 (just vm-create が作る名前と合わせる)')
param targetVMName string = 'vm-rbtarget'

@description('操作対象 VM のリソースグループ (既定はこのデプロイ先 RG)')
param targetVMResourceGroup string = resourceGroup().name

@description('スケジュール実行時の既定アクション')
@allowed([
  'Start'
  'Stop'
])
param defaultAction string = 'Stop'

@description('Runbook 名')
param runbookName string = 'Manage-VMPower'

@description('スケジュールを作るかどうか (通常の deploy では false。just schedule で true)')
param deploySchedule bool = false

@description('スケジュール名')
param scheduleName string = 'sched-nightly-stop'

@description('スケジュールの頻度')
param scheduleFrequency string = 'Day'

@description('スケジュールの間隔')
param scheduleInterval int = 1

@description('スケジュールのタイムゾーン')
param scheduleTimeZone string = 'Tokyo Standard Time'

// utcNow() はパラメータ既定値でのみ使える。デプロイ時刻 + 1 時間を初回実行時刻にする
// (必須かつ未来でなければならず、再デプロイでも常に有効になるようにするため)。
@description('スケジュール初回実行時刻 (既定はデプロイ時刻 + 1 時間)')
param scheduleStartTime string = dateTimeAdd(utcNow('yyyy-MM-ddTHH:mm:ssZ'), 'PT1H')

@description('リソースに付けるタグ')
param tags object = {
  Environment: 'Development'
  Project: 'AutomateRunbook'
  ManagedBy: 'Bicep'
}

var automationAccountName = 'aa-${prefix}'

// ----------------------------------------------------------------------------
// 土台 (Automation Account / MI / ロール / 変数)
// ----------------------------------------------------------------------------
module account './modules/account.bicep' = {
  name: 'account'
  params: {
    location: location
    automationAccountName: automationAccountName
    targetVMName: targetVMName
    targetVMResourceGroup: targetVMResourceGroup
    defaultAction: defaultAction
    tags: tags
  }
}

// ----------------------------------------------------------------------------
// Runbook (主役) + 任意のスケジュール
// ----------------------------------------------------------------------------
module runbook './modules/runbook.bicep' = {
  name: 'runbook'
  params: {
    automationAccountName: account.outputs.automationAccountName
    location: location
    runbookName: runbookName
    deploySchedule: deploySchedule
    scheduleName: scheduleName
    scheduleFrequency: scheduleFrequency
    scheduleInterval: scheduleInterval
    scheduleTimeZone: scheduleTimeZone
    scheduleStartTime: scheduleStartTime
    tags: tags
  }
}

// ----------------------------------------------------------------------------
// 出力 (justfile が各レシピで参照)
// ----------------------------------------------------------------------------
@description('Automation Account 名')
output automationAccountName string = account.outputs.automationAccountName

@description('Automation Account のリソース ID (az rest で jobs/variables を叩くのに使う)')
output automationAccountId string = account.outputs.automationAccountId

@description('Runbook 名')
output runbookName string = runbook.outputs.runbookName

@description('Automation Account の system-assigned マネージド ID の principalId (ロール付け外しに使う)')
output principalId string = account.outputs.principalId

@description('操作対象 VM 名')
output targetVMName string = targetVMName
