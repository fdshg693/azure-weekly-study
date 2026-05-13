@description('Azure リソースをデプロイするリージョン')
param location string

@description('Storage Account 名 (3-24 文字、英小文字と数字のみ)')
param storageAccountName string

@description('リソースに適用するタグ')
param tags object

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
  }
  tags: tags
}

// VM 状態 (lastAccessUtc) を保存する Table。
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource stateTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'vmstate'
}

output storageAccountName string = storage.name
output storageAccountId string = storage.id
