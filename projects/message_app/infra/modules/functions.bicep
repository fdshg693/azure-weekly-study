// Azure Functions（書き込み=メッセージ送信）。Linux 従量課金(Consumption / Y1)。
// 専用のストレージアカウントと従量プランを作る。

@description('リージョン')
param location string

@description('Function App 名（グローバル一意・小文字）')
param functionAppName string

@description('Functions 用ストレージ名（英小文字+数字・24 文字以内）')
param storageName string

@description('Cosmos/Redis などの追加アプリ設定。{name, value} の配列')
param appSettings array = []

param tags object = {}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${functionAppName}-plan'
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

var storageConn = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}'

// Functions ランタイムに必須の設定 + 呼び出し側から渡るデータ接続設定をマージ
var baseSettings = [
  {
    name: 'AzureWebJobsStorage'
    value: storageConn
  }
  {
    name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
    value: storageConn
  }
  {
    name: 'WEBSITE_CONTENTSHARE'
    value: toLower(functionAppName)
  }
  {
    name: 'FUNCTIONS_EXTENSION_VERSION'
    value: '~4'
  }
  {
    name: 'FUNCTIONS_WORKER_RUNTIME'
    value: 'python'
  }
]

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      appSettings: concat(baseSettings, appSettings)
      cors: {
        allowedOrigins: [ '*' ]
      }
      ftpsState: 'Disabled'
    }
  }
}

output defaultHostName string = functionApp.properties.defaultHostName
output functionAppName string = functionApp.name
