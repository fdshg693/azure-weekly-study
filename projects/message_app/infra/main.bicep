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

@description('JWT 署名鍵（HMAC）。未指定なら毎デプロイで生成。api が発行し bff が検証する')
@secure()
param jwtSecret string = newGuid()

@description('JWT 有効期間（秒）')
param jwtTtlSeconds string = '3600'

// グローバル一意 / 文字数制約に合わせて名前を組み立てる
var names = {
  cosmos: toLower('cosmos-${prefix}-${suffix}')
  redis: toLower('redis-${prefix}-${suffix}')
  plan: 'plan-${prefix}'
  api: toLower('app-${prefix}-api-${suffix}')
  bff: toLower('app-${prefix}-bff-${suffix}')
  func: toLower('func-${prefix}-${suffix}')
  storage: take(toLower('st${replace(prefix, '-', '')}${suffix}'), 24)
  acsEmail: toLower('acs-email-${prefix}-${suffix}')
  acs: toLower('acs-${prefix}-${suffix}')
  db: 'messageapp'
}

// 検証メールのリンクは BFF の公開オリジンを使う。App Service の既定ホスト名は
// 名前から確定するので、bff モジュールの出力を待たずに組み立てられる
// （functions → bff の循環依存を避けるため）。
var bffPublicUrl = 'https://${names.bff}.azurewebsites.net'

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

// --- 通信（ACS Email・検証メール送信） --------------------------------------
module communication './modules/communication.bicep' = {
  name: 'communication'
  params: {
    emailServiceName: names.acsEmail
    communicationName: names.acs
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
      // login が JWT を発行するための鍵 / 有効期間
      {
        name: 'JWT_SECRET'
        value: jwtSecret
      }
      {
        name: 'JWT_TTL_SECONDS'
        value: jwtTtlSeconds
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
    // データ接続に加え、検証メール送信(ACS)の設定を渡す
    appSettings: concat(dataSettings, [
      {
        name: 'EMAIL_MODE'
        value: 'acs'
      }
      {
        name: 'APP_BASE_URL'
        value: bffPublicUrl
      }
      {
        name: 'ACS_CONNECTION_STRING'
        value: communication.outputs.connectionString
      }
      {
        name: 'ACS_SENDER_ADDRESS'
        value: communication.outputs.senderAddress
      }
    ])
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
      // BFF が下流転送前に JWT を検証するための鍵（api と同じ値）
      {
        name: 'JWT_SECRET'
        value: jwtSecret
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
output acsSenderAddress string = communication.outputs.senderAddress
output functionAppName string = functions.outputs.functionAppName
output apiAppName string = api.outputs.name
output bffAppName string = bff.outputs.name
