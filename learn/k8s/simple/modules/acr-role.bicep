// 記事の `az aks create --attach-acr` 相当:
// AKS の kubelet マネージド ID に、対象 ACR スコープで AcrPull ロールを付与する。
// これにより Pod は imagePullSecret なしで ACR からイメージを pull できる。

@description('AcrPull を付与する対象の ACR 名')
param acrName string

@description('AKS の kubelet マネージド ID の Object ID')
param kubeletObjectId string

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
}

// AcrPull の組み込みロール定義 ID
var acrPullRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, kubeletObjectId, acrPullRoleDefinitionId)
  scope: acr
  properties: {
    principalId: kubeletObjectId
    roleDefinitionId: acrPullRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}
