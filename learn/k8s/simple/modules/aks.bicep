@description('Azure リソースをデプロイするリージョン')
param location string

@description('AKS クラスタ名')
param aksName string

@description('AKS のノード数')
param nodeCount int

@description('AKS ノードの VM サイズ')
param nodeVmSize string

@description('Kubernetes バージョン。空文字なら AKS の既定を使う')
param kubernetesVersion string

@description('リソースに適用するタグ')
param tags object

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: aksName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    dnsPrefix: aksName
    kubernetesVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    agentPoolProfiles: [
      {
        name: 'system'
        count: nodeCount
        vmSize: nodeVmSize
        mode: 'System'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
      }
    ]
    // addon) を有効化し、ingressClassName: webapprouting.kubernetes.azure.com を使えるようにする。
    ingressProfile: {
      webAppRouting: {
        enabled: true
      }
    }
  }
  tags: tags
}

output aksName string = aks.name
output aksId string = aks.id

// --attach-acr が AcrPull を付与する相手 = 各ノードの kubelet マネージド ID。
output kubeletObjectId string = aks.properties.identityProfile.kubeletidentity.objectId
