// 汎用 Web App モジュール。BFF(Node) と 読み取り API(Python) の両方をこれで作る。

@description('リージョン')
param location string

@description('Web App 名（グローバル一意・小文字）')
param siteName string

@description('相乗りする App Service プランの ID')
param planId string

@description('ランタイム。例: NODE|20-lts / PYTHON|3.11')
param linuxFxVersion string

@description('起動コマンド（Python の uvicorn 等）。空なら既定起動')
param appCommandLine string = ''

@description('アプリ設定（環境変数）の配列。{name, value} の形')
param appSettings array = []

param tags object = {}

resource site 'Microsoft.Web/sites@2024-04-01' = {
  name: siteName
  location: location
  tags: tags
  properties: {
    serverFarmId: planId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      appCommandLine: appCommandLine
      appSettings: appSettings
      ftpsState: 'Disabled'
      alwaysOn: true
    }
  }
}

output name string = site.name
output defaultHostName string = site.properties.defaultHostName
