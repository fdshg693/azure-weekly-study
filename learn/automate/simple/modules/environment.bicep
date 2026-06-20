// ============================================================================
// Container Apps Job を動かすための「土台」一式
// ============================================================================
//   - Log Analytics Workspace        … 実行ログ (stdout) の保存先
//   - Container Apps Environment      … Job / App が同居する実行環境 (境界)
//   - Azure Container Registry (ACR)  … 自作ワーカーイメージの置き場所
//   - User-Assigned Managed Identity  … ACR から pull するための ID
//   - AcrPull ロール付与              … その ID に ACR の pull 権限を与える
//
// Job 本体 (主役) は job.bicep に分離してある。ここは "周辺インフラ" に徹する。

@description('デプロイ先リージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('一意性確保用サフィックス')
param suffix string

@description('リソースに付けるタグ')
param tags object

// ----------------------------------------------------------------------------
// 名前 (ACR は英数字のみ・グローバル一意)
// ----------------------------------------------------------------------------
var lawName = 'law-${prefix}'
var envName = 'cae-${prefix}'
var acrName = take(toLower('acr${prefix}${suffix}'), 50)
var uamiName = 'uami-${prefix}'

// ----------------------------------------------------------------------------
// Log Analytics Workspace
// ----------------------------------------------------------------------------
resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: lawName
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ----------------------------------------------------------------------------
// Container Apps Environment
//   appLogsConfiguration で stdout を上の Log Analytics に流す。
// ----------------------------------------------------------------------------
resource managedEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: envName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
  }
}

// ----------------------------------------------------------------------------
// Azure Container Registry (admin user は使わず、MI + AcrPull で pull する)
// ----------------------------------------------------------------------------
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
  }
}

// ----------------------------------------------------------------------------
// User-Assigned Managed Identity + AcrPull ロール
//   Job はこの ID を assign し、registries[].identity で参照して ACR から pull する。
// ----------------------------------------------------------------------------
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
  tags: tags
}

// AcrPull ロール定義 ID (固定 GUID)
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, uami.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ----------------------------------------------------------------------------
// 出力 (main.bicep / justfile が参照)
// ----------------------------------------------------------------------------
output environmentId string = managedEnv.id
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output uamiResourceId string = uami.id
output lawCustomerId string = law.properties.customerId
