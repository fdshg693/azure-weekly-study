// ============================================================================
// Runbook (このプロジェクトの主役) と、任意のスケジュール
// ============================================================================
// - runbook は「空のドラフト (draft: {})」で作る。本文はデプロイ後に
//   justfile (az automation runbook replace-content + publish) でアップロードする。
//   → simple が「Job を先に作り、後から az acr build でイメージを用意」したのと同じ発想。
//
// - スケジュールは deploySchedule=true のときだけ作る。Automation のスケジュールは
//   いったん作ると frequency/startTime をほぼ変更できない (immutable) ため、
//   何度も再実行する通常の deploy には含めず、専用レシピ (just schedule) で一度だけ作る。

@description('Automation Account 名 (親)')
param automationAccountName string

@description('デプロイ先リージョン')
param location string

@description('Runbook 名')
param runbookName string

@description('リソースに付けるタグ')
param tags object

@description('true のときだけスケジュールと jobSchedule を作る')
param deploySchedule bool = false

@description('スケジュール名')
param scheduleName string = 'sched-nightly-stop'

@description('スケジュールの頻度 (Day / Hour / Week など)')
param scheduleFrequency string = 'Day'

@description('スケジュールの間隔 (frequency と組み合わせる)')
param scheduleInterval int = 1

@description('スケジュールのタイムゾーン。Container Apps の cron が UTC 固定なのと対照的にここで指定できる')
param scheduleTimeZone string = 'Tokyo Standard Time'

@description('初回実行時刻 (ISO8601)。必須かつ未来でなければならない。既定は「デプロイ時刻 + 1 時間」')
param scheduleStartTime string

// 親 Automation Account を既存参照する (この module は account.bicep の後に走る)。
resource account 'Microsoft.Automation/automationAccounts@2023-11-01' existing = {
  name: automationAccountName
}

// ----------------------------------------------------------------------------
// Runbook 本体。draft: {} で中身は空。runbookType は Windows PowerShell 5.1。
// ----------------------------------------------------------------------------
resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: account
  name: runbookName
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell'
    logProgress: false
    logVerbose: false
    draft: {}
  }
}

// ----------------------------------------------------------------------------
// スケジュール (任意)。タイムゾーン指定ができるのが Automation の特徴。
// ----------------------------------------------------------------------------
resource schedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = if (deploySchedule) {
  parent: account
  name: scheduleName
  properties: {
    description: 'runbook を定期実行するスケジュール'
    frequency: scheduleFrequency
    interval: scheduleInterval
    startTime: scheduleStartTime
    timeZone: scheduleTimeZone
  }
}

// ----------------------------------------------------------------------------
// jobSchedule = 「どのスケジュールで、どの runbook を走らせるか」の紐付け。
//   名前は GUID。引数を渡さないので、スケジュール実行は Automation 変数を参照する。
// ----------------------------------------------------------------------------
resource jobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (deploySchedule) {
  parent: account
  name: guid(automationAccountName, runbookName, scheduleName)
  properties: {
    runbook: {
      name: runbookName
    }
    schedule: {
      name: scheduleName
    }
  }
  dependsOn: [
    runbook
    schedule
  ]
}

output runbookName string = runbook.name
