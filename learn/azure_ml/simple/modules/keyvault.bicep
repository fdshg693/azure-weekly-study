// 付随リソース: Azure Key Vault (記事 2 章)
// ストレージの接続文字列・データストアの資格情報などシークレットの保管庫。
// アクセスポリシー方式 (enableRbacAuthorization=false) にしておくと、Workspace 作成時に
// Azure ML の RP が自分のマネージド ID 向けのアクセスポリシーを自動で足してくれる。

@description('Azure リソースをデプロイするリージョン')
param location string

@description('Key Vault 名 (3-24 文字、英数字とハイフン、グローバル一意)')
param keyVaultName string

@description('リソースに適用するタグ')
param tags object

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: false
    accessPolicies: []
  }
  tags: tags
}

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
