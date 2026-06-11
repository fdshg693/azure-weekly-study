// 付随リソース: Azure Storage (記事 2 章)
// 成果物・ジョブログ・アップロードしたデータ・既定 Datastore の置き場。
// allowSharedKeyAccess を無効化しないので、既定 Datastore は「資格情報(キー)ベース」
// として作られ、ローカルからの code/data アップロードが RBAC なしで通る。

@description('Azure リソースをデプロイするリージョン')
param location string

@description('Storage アカウント名 (3-24 文字、英小文字と数字のみ、グローバル一意)')
param storageName string

@description('リソースに適用するタグ')
param tags object

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: { enabled: true }
        file: { enabled: true }
      }
    }
  }
  tags: tags
}

output storageId string = storage.id
output storageName string = storage.name
