// ============================================================================
// Container Apps Job (このプロジェクトの主役)
// ============================================================================
// 「常駐する App」ではなく「起動して終了する Job」。triggerType=Schedule にして
// cron で定期実行しつつ、`az containerapp job start` で手動起動もできる。
//
// 因果実験で出し入れするパラメータ (cronExpression / replicaRetryLimit /
// parallelism / replicaCompletionCount / failJob) は全てここに集約してある。

@description('デプロイ先リージョン')
param location string

@description('Job 名')
param jobName string

@description('Container Apps Environment のリソース ID')
param environmentId string

@description('ACR ログインサーバ (例: acrxxx.azurecr.io)')
param acrLoginServer string

@description('pull に使う User-Assigned Managed Identity のリソース ID')
param uamiResourceId string

@description('実行するイメージ (リポジトリ:タグ)')
param image string

@description('スケジュール (5 フィールド cron, UTC)。既定は 5 分ごと')
param cronExpression string = '*/5 * * * *'

@description('1 実行あたり同時に走らせるレプリカ数')
@minValue(1)
param parallelism int = 1

@description('1 実行を成功とみなすのに必要な成功レプリカ数')
@minValue(1)
param replicaCompletionCount int = 1

@description('レプリカ失敗時のリトライ回数')
@minValue(0)
param replicaRetryLimit int = 1

@description('1 レプリカのタイムアウト秒数')
param replicaTimeout int = 120

@description('ワーカーがログに出すメッセージ')
param jobMessage string = 'hello from container apps job'

@description('true にするとワーカーを exit 1 で失敗させる (リトライ観察用)')
param failJob bool = false

@description('リソースに付けるタグ')
param tags object

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: jobName
  location: location
  tags: tags
  // ACR から pull するための User-Assigned MI を割り当てる。
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiResourceId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    configuration: {
      // Schedule トリガー: cron で定期起動。手動起動 (job start) も併用できる。
      triggerType: 'Schedule'
      replicaTimeout: replicaTimeout
      replicaRetryLimit: replicaRetryLimit
      scheduleTriggerConfig: {
        cronExpression: cronExpression
        parallelism: parallelism
        replicaCompletionCount: replicaCompletionCount
      }
      // どの MI で ACR にアクセスするか。admin user を使わずキーレスで pull。
      registries: [
        {
          server: acrLoginServer
          identity: uamiResourceId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'worker'
          image: image
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            { name: 'JOB_MESSAGE', value: jobMessage }
            { name: 'WORK_SECONDS', value: '3' }
            { name: 'FAIL_JOB', value: string(failJob) }
          ]
        }
      ]
    }
  }
}

output jobName string = job.name
