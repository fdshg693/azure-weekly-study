@description('Azure リソースをデプロイするリージョン')
param location string

@description('Key Vault 名（グローバル一意）')
param keyVaultName string

@description('Key Vault のテナント ID')
param tenantId string = subscription().tenantId

@description('BACKEND_SHARED_SECRET シークレットの名前')
param backendSecretName string = 'backend-shared-secret'

@secure()
@description('BACKEND_SHARED_SECRET の値')
param backendSharedSecret string

@description('リソースに適用するタグ')
param tags object = {}

// RBAC 認可モードに統一する。Access Policy ベースは旧式なので学習用にも採用しない。
resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: null
    publicNetworkAccess: 'Enabled'
  }
  tags: tags
}

resource backendSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: backendSecretName
  properties: {
    value: backendSharedSecret
    attributes: {
      enabled: true
    }
  }
}

output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
// versionless URI: Function App の Key Vault reference / APIM の named value で最新版を自動追従する。
output backendSecretUri string = '${keyVault.properties.vaultUri}secrets/${backendSecret.name}'
