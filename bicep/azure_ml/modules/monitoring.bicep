// 付随リソース: Application Insights (記事 2 章 / 9 章)
// 推論エンドポイントの監視・診断情報の収集に使う。
// 現在の App Insights は「ワークスペースベース」が必須なので、土台に Log Analytics
// ワークスペースも 1 つ作って紐づける。

@description('Azure リソースをデプロイするリージョン')
param location string

@description('Log Analytics ワークスペース名')
param logAnalyticsName string

@description('Application Insights 名')
param appInsightsName string

@description('リソースに適用するタグ')
param tags object

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
  tags: tags
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
  tags: tags
}

output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
