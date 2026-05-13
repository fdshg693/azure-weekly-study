@description('Azure リソースをデプロイするリージョン')
param location string

@description('Function App 名')
param functionAppName string

@description('App Service Plan のリソース ID')
param servicePlanId string

@description('Storage Account 名')
param storageAccountName string

@description('Python ランタイムのバージョン')
param pythonVersion string

@description('リソースに適用するタグ')
param tags object

@description('BACKEND_SHARED_SECRET を格納している Key Vault シークレットの URI (versionless)')
param backendSecretUri string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// ----------------------------------------------------------------------------
// App Settings を意味別に組み立てる
// ----------------------------------------------------------------------------

// Functions ランタイム本体の設定
var runtimeSettings = [
  { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
  { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
  { name: 'AzureWebJobsFeatureFlags', value: 'EnableWorkerIndexing' }
]

// AzureWebJobsStorage の identity-based connection。
// ホストランタイムは Managed Identity で Storage を呼ぶため、接続文字列や key は持たない。
var storageIdentitySettings = [
  { name: 'AzureWebJobsStorage__accountName', value: storageAccount.name }
  { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
  { name: 'AzureWebJobsStorage__blobServiceUri', value: storageAccount.properties.primaryEndpoints.blob }
  { name: 'AzureWebJobsStorage__queueServiceUri', value: storageAccount.properties.primaryEndpoints.queue }
  { name: 'AzureWebJobsStorage__tableServiceUri', value: storageAccount.properties.primaryEndpoints.table }
]

// Premium プランの content share も identity-based に統一。
// 別途 Storage File Data SMB Share Contributor ロールが必要。
var contentShareSettings = [
  { name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING__accountName', value: storageAccount.name }
  { name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING__credential', value: 'managedidentity' }
  { name: 'WEBSITE_CONTENTSHARE', value: toLower(functionAppName) }
]

// Oryx でリモートビルドを行わせる。
var buildSettings = [
  { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
  { name: 'ENABLE_ORYX_BUILD', value: 'true' }
]

// BACKEND_SHARED_SECRET は Key Vault に格納し、Function App は Managed Identity で取り出す。
var secretSettings = [
  { name: 'BACKEND_SHARED_SECRET', value: '@Microsoft.KeyVault(SecretUri=${backendSecretUri})' }
]

var appSettings = concat(runtimeSettings, storageIdentitySettings, contentShareSettings, buildSettings, secretSettings)

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: servicePlanId
    httpsOnly: true
    keyVaultReferenceIdentity: 'SystemAssigned'
    siteConfig: {
      linuxFxVersion: 'Python|${pythonVersion}'
      appSettings: appSettings
      cors: {
        allowedOrigins: ['https://portal.azure.com']
      }
    }
  }
  tags: tags
}

output functionAppName string = functionApp.name
output functionDefaultHostName string = functionApp.properties.defaultHostName
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output functionAppPrincipalId string = functionApp.identity.principalId
