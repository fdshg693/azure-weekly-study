@description('Azure リソースをデプロイするリージョン')
param location string

@description('ACR 名 (5-50 文字、英小文字と数字のみ、グローバル一意)')
param acrName string

@description('リソースに適用するタグ')
param tags object

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  sku: { name: 'Basic' }
  properties: {
    // pull は AKS の kubelet ID に AcrPull ロールで許可するため admin user は不要。
    adminUserEnabled: false
  }
  tags: tags
}

output acrName string = acr.name
output acrId string = acr.id
output acrLoginServer string = acr.properties.loginServer
