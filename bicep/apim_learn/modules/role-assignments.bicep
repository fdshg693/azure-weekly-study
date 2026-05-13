// ============================================================================
// RBAC ロール割り当てを一括管理するモジュール
// ============================================================================
// 学習目的：
//   - Microsoft.Authorization/roleAssignments の scope と principalId の取り回し
//   - guid(scope, principal, role) による冪等な role assignment 名生成
//   - 組み込みロールの role definition GUID（unique across tenants）

@description('Storage Account 名')
param storageAccountName string

@description('Key Vault 名')
param keyVaultName string

@description('Function App の System-Assigned Managed Identity の principalId')
param functionAppPrincipalId string

@description('APIM の System-Assigned Managed Identity の principalId')
param apimPrincipalId string

@description('AOAI を有効にしているか')
param enableAzureOpenAiApi bool = false

@description('Azure OpenAI アカウント名（enableAzureOpenAiApi=true のときのみ参照）')
param azureOpenAiAccountName string = ''

// ----------------------------------------------------------------------------
// 組み込みロール定義 ID（Azure グローバル定数）
// ----------------------------------------------------------------------------
var roleDefinitions = {
  storageBlobDataOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  storageQueueDataContributor: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  storageTableDataContributor: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  storageFileDataSmbShareContributor: '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb'
  cognitiveServicesOpenAiUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource azureOpenAiAccount 'Microsoft.CognitiveServices/accounts@2025-12-01' existing = if (enableAzureOpenAiApi) {
  name: azureOpenAiAccountName
}

// ----------------------------------------------------------------------------
// Function App MI → Storage Account
// AzureWebJobsStorage identity-based connection が必要とする 4 ロール。
// ----------------------------------------------------------------------------
resource fnStorageBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionAppPrincipalId, roleDefinitions.storageBlobDataOwner)
  properties: {
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageBlobDataOwner)
  }
}

resource fnStorageQueue 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionAppPrincipalId, roleDefinitions.storageQueueDataContributor)
  properties: {
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageQueueDataContributor)
  }
}

resource fnStorageTable 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionAppPrincipalId, roleDefinitions.storageTableDataContributor)
  properties: {
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageTableDataContributor)
  }
}

resource fnStorageFile 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionAppPrincipalId, roleDefinitions.storageFileDataSmbShareContributor)
  properties: {
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageFileDataSmbShareContributor)
  }
}

// ----------------------------------------------------------------------------
// Function App MI → Key Vault (BACKEND_SHARED_SECRET 読み取り)
// ----------------------------------------------------------------------------
resource fnKeyVault 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, functionAppPrincipalId, roleDefinitions.keyVaultSecretsUser)
  properties: {
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.keyVaultSecretsUser)
  }
}

// ----------------------------------------------------------------------------
// APIM MI → Key Vault (named value バック用シークレット読み取り)
// ----------------------------------------------------------------------------
resource apimKeyVault 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, apimPrincipalId, roleDefinitions.keyVaultSecretsUser)
  properties: {
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.keyVaultSecretsUser)
  }
}

// ----------------------------------------------------------------------------
// APIM MI → Azure OpenAI (token-based 呼び出し)
// AOAI 側で disableLocalAuth:true としているため、これが無いと APIM 経由の呼び出しが 401 になる。
// ----------------------------------------------------------------------------
resource apimAzureOpenAi 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableAzureOpenAiApi) {
  scope: azureOpenAiAccount
  name: guid(resourceId('Microsoft.CognitiveServices/accounts', azureOpenAiAccountName), apimPrincipalId, roleDefinitions.cognitiveServicesOpenAiUser)
  properties: {
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.cognitiveServicesOpenAiUser)
  }
}
