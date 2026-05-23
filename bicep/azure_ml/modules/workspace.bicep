// Azure Machine Learning Workspace (記事 1 章の「中心」)
// Storage / Key Vault / Application Insights を「付随リソース」として束ねる。
// Container Registry はあえて渡さない: 初回 Environment ビルド時に Azure ML が
// 自動作成する (記事 2 章の注記どおり)。
// SystemAssigned マネージド ID を持たせることで、ジョブ/エンドポイントが
// 付随リソースへキーレスでアクセスできる土台になる (記事 3 章の DefaultAzureCredential)。

@description('Azure リソースをデプロイするリージョン')
param location string

@description('Workspace 名 (3-33 文字、英数字とハイフン)')
param workspaceName string

@description('付随リソース: Storage アカウントのリソース ID')
param storageId string

@description('付随リソース: Key Vault のリソース ID')
param keyVaultId string

@description('付随リソース: Application Insights のリソース ID')
param appInsightsId string

@description('リソースに適用するタグ')
param tags object

resource workspace 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: workspaceName
  location: location
  identity: { type: 'SystemAssigned' }
  sku: { name: 'Basic', tier: 'Basic' }
  properties: {
    friendlyName: workspaceName
    storageAccount: storageId
    keyVault: keyVaultId
    applicationInsights: appInsightsId
  }
  tags: tags
}

output workspaceName string = workspace.name
output workspaceId string = workspace.id
output principalId string = workspace.identity.principalId
