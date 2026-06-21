// ============================================================================
// メッセージアプリ MVP — インフラ一式（PLAN.md の構成を Bicep 化）
// ============================================================================
// 構成: BFF(Node/App Service) + 読み取り API(Python/App Service) +
//        書き込み(Functions) + Cosmos DB + Azure Cache for Redis
//
// デプロイ:
//   az deployment group create -g <RG> --template-file main.bicep \
//     --parameters prefix=msgapp
// ============================================================================

@description('リージョン')
param location string = resourceGroup().location

@description('リソース名プレフィックス（2〜10 文字）')
@minLength(2)
@maxLength(10)
param prefix string = 'msgapp'

@description('一意サフィックス（既定はリソースグループ ID から生成）')
param suffix string = uniqueString(resourceGroup().id)

@description('共通タグ')
param tags object = {
  Project: 'message_app'
  Environment: 'Development'
  ManagedBy: 'Bicep'
}

// グローバル一意 / 文字数制約に合わせて名前を組み立てる
var names = {
  cosmos: toLower('cosmos-${prefix}-${suffix}')
  redis: toLower('redis-${prefix}-${suffix}')
  plan: 'plan-${prefix}'
  api: toLower('app-${prefix}-api-${suffix}')
  bff: toLower('app-${prefix}-bff-${suffix}')
  func: toLower('func-${prefix}-${suffix}')
  storage: take(toLower('st${replace(prefix, '-', '')}${suffix}'), 24)
  db: 'messageapp'
}

// --- データ層 ---------------------------------------------------------------
module cosmos './modules/cosmos.bicep' = {
  name: 'cosmos'
  params: {
    location: location
    accountName: names.cosmos
    databaseName: names.db
    tags: tags
  }
}

module redis './modules/redis.bicep' = {
  name: 'redis'
  params: {
    location: location
    redisName: names.redis
    tags: tags
  }
}

module plan './modules/plan.bicep' = {
  name: 'plan'
  params: {
    location: location
    planName: names.plan
    tags: tags
  }
}

// 読み取り API / Functions に共通で渡す Cosmos・Redis 接続設定
var dataSettings = [
  {
    name: 'COSMOS_ENDPOINT'
    value: cosmos.outputs.endpoint
  }
  {
    name: 'COSMOS_KEY'
    value: cosmos.outputs.primaryKey
  }
  {
    name: 'COSMOS_DB'
    value: names.db
  }
  {
    name: 'COSMOS_VERIFY_TLS'
    value: 'true'
  }
  {
    name: 'REDIS_HOST'
    value: redis.outputs.hostName
  }
  {
    name: 'REDIS_PORT'
    value: string(redis.outputs.sslPort)
  }
  {
    name: 'REDIS_PASSWORD'
    value: redis.outputs.primaryKey
  }
  {
    name: 'REDIS_SSL'
    value: 'true'
  }
  {
    name: 'CACHE_TTL_SECONDS'
    value: '60'
  }
]

// --- 読み取り API（FastAPI / App Service） ----------------------------------
module api './modules/webapp.bicep' = {
  name: 'api'
  params: {
    location: location
    siteName: names.api
    planId: plan.outputs.planId
    linuxFxVersion: 'PYTHON|3.11'
    appCommandLine: 'python -m uvicorn main:app --host 0.0.0.0 --port 8000'
    appSettings: concat(dataSettings, [
      {
        name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
        value: 'true'
      }
      {
        name: 'WEBSITES_PORT'
        value: '8000'
      }
    ])
    tags: tags
  }
}

// --- 書き込み（Azure Functions） --------------------------------------------
module functions './modules/functions.bicep' = {
  name: 'functions'
  params: {
    location: location
    functionAppName: names.func
    storageName: names.storage
    appSettings: dataSettings
    tags: tags
  }
}

// --- BFF（Express / App Service） -------------------------------------------
// 下流の URL（API / Functions）が確定してから作る
module bff './modules/webapp.bicep' = {
  name: 'bff'
  params: {
    location: location
    siteName: names.bff
    planId: plan.outputs.planId
    linuxFxVersion: 'NODE|20-lts'
    appSettings: [
      {
        name: 'API_BASE_URL'
        value: 'https://${api.outputs.defaultHostName}'
      }
      {
        name: 'FUNCTIONS_BASE_URL'
        value: 'https://${functions.outputs.defaultHostName}'
      }
      {
        name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
        value: 'true'
      }
      {
        name: 'WEBSITE_NODE_DEFAULT_VERSION'
        value: '~20'
      }
    ]
    tags: tags
  }
}

// --- 出力（デプロイ後の動作確認に使う） -------------------------------------
output bffUrl string = 'https://${bff.outputs.defaultHostName}'
output apiUrl string = 'https://${api.outputs.defaultHostName}'
output functionsUrl string = 'https://${functions.outputs.defaultHostName}'
output cosmosAccount string = cosmos.outputs.accountName
output functionAppName string = functions.outputs.functionAppName
output apiAppName string = api.outputs.name
output bffAppName string = bff.outputs.name
