// ============================================================================
// automate/simple — Container Apps Job が主役の最小「自動化」プロジェクト
// ============================================================================
// 「起動 → 仕事 → 終了」を 1 回の実行とする Job を、cron で定期実行する。
// 周辺インフラ (Log Analytics / Environment / ACR / MI) は modules/environment.bicep、
// Job 本体は modules/job.bicep に分離している。
//
// デプロイ:
//   az deployment group create \
//     --resource-group rg-automate-simple \
//     --template-file main.bicep --parameters main.bicepparam
//
// 注意: Job はイメージを参照するだけなのでイメージ未ビルドでもデプロイは通る。
//       先に (または直後に) `just build` でイメージを push しないと、実行は失敗する。

@description('デプロイ先リージョン')
param location string = resourceGroup().location

@description('リソース名のプレフィックス')
@minLength(1)
@maxLength(12)
param prefix string = 'cajob'

@description('一意性確保用サフィックス (既定は RG ID 由来)')
param suffix string = uniqueString(resourceGroup().id)

@description('イメージのリポジトリ名')
param imageRepository string = 'hello-job'

@description('イメージのタグ')
param imageTag string = 'v1'

@description('スケジュール (5 フィールド cron, UTC)')
param cronExpression string = '*/5 * * * *'

@description('1 実行あたり同時に走らせるレプリカ数')
param parallelism int = 1

@description('1 実行を成功とみなすのに必要な成功レプリカ数')
param replicaCompletionCount int = 1

@description('レプリカ失敗時のリトライ回数')
param replicaRetryLimit int = 1

@description('ワーカーがログに出すメッセージ')
param jobMessage string = 'hello from container apps job'

@description('true にするとワーカーを exit 1 で失敗させる (リトライ観察用)')
param failJob bool = false

@description('リソースに付けるタグ')
param tags object = {
  Environment: 'Development'
  Project: 'AutomateContainerJob'
  ManagedBy: 'Bicep'
}

var jobName = 'job-${prefix}-hello'

// ----------------------------------------------------------------------------
// 土台 (Log Analytics / Environment / ACR / MI + AcrPull)
// ----------------------------------------------------------------------------
module environment './modules/environment.bicep' = {
  name: 'environment'
  params: {
    location: location
    prefix: prefix
    suffix: suffix
    tags: tags
  }
}

// ----------------------------------------------------------------------------
// Job 本体。イメージ参照は ACR ログインサーバ + リポジトリ:タグ で組み立てる。
// ----------------------------------------------------------------------------
module job './modules/job.bicep' = {
  name: 'job'
  params: {
    location: location
    jobName: jobName
    environmentId: environment.outputs.environmentId
    acrLoginServer: environment.outputs.acrLoginServer
    uamiResourceId: environment.outputs.uamiResourceId
    image: '${environment.outputs.acrLoginServer}/${imageRepository}:${imageTag}'
    cronExpression: cronExpression
    parallelism: parallelism
    replicaCompletionCount: replicaCompletionCount
    replicaRetryLimit: replicaRetryLimit
    jobMessage: jobMessage
    failJob: failJob
    tags: tags
  }
}

// ----------------------------------------------------------------------------
// 出力 (justfile が各レシピで参照)
// ----------------------------------------------------------------------------
@description('ACR 名 (az acr build の --registry に使う)')
output acrName string = environment.outputs.acrName

@description('Job 名 (job start / execution list に使う)')
output jobName string = job.outputs.jobName

@description('Log Analytics の customerId (ログ照会に使う)')
output lawCustomerId string = environment.outputs.lawCustomerId
