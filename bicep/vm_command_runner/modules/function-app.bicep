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

@description('対象 VM のリソース ID')
param targetVmResourceId string

@description('対象 VM 名')
param targetVmName string

@description('対象 VM のリソースグループ名')
param targetVmResourceGroup string

@description('アイドル分数しきい値')
param idleMinutesBeforeStop int

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// ----------------------------------------------------------------------------
// App Settings
// ----------------------------------------------------------------------------
var runtimeSettings = [
  { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
  { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
  { name: 'AzureWebJobsFeatureFlags', value: 'EnableWorkerIndexing' }
]

// AzureWebJobsStorage を identity-based 接続に
var storageIdentitySettings = [
  { name: 'AzureWebJobsStorage__accountName', value: storageAccount.name }
  { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
  { name: 'AzureWebJobsStorage__blobServiceUri', value: storageAccount.properties.primaryEndpoints.blob }
  { name: 'AzureWebJobsStorage__queueServiceUri', value: storageAccount.properties.primaryEndpoints.queue }
  { name: 'AzureWebJobsStorage__tableServiceUri', value: storageAccount.properties.primaryEndpoints.table }
]

// Premium content share も identity-based
var contentShareSettings = [
  { name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING__accountName', value: storageAccount.name }
  { name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING__credential', value: 'managedidentity' }
  { name: 'WEBSITE_CONTENTSHARE', value: toLower(functionAppName) }
]

var buildSettings = [
  { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
  { name: 'ENABLE_ORYX_BUILD', value: 'true' }
]

// アプリ固有の設定
var appConfigSettings = [
  { name: 'TARGET_VM_RESOURCE_ID', value: targetVmResourceId }
  { name: 'TARGET_VM_NAME', value: targetVmName }
  { name: 'TARGET_VM_RESOURCE_GROUP', value: targetVmResourceGroup }
  { name: 'STORAGE_ACCOUNT_NAME', value: storageAccountName }
  { name: 'STORAGE_TABLE_NAME', value: 'vmstate' }
  { name: 'IDLE_MINUTES_BEFORE_STOP', value: string(idleMinutesBeforeStop) }
  { name: 'SUBSCRIPTION_ID', value: subscription().subscriptionId }
]

var appSettings = concat(runtimeSettings, storageIdentitySettings, contentShareSettings, buildSettings, appConfigSettings)

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: servicePlanId
    httpsOnly: true
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
