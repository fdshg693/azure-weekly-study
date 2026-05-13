// ============================================================================
// RBAC ロール割り当てを一括管理するモジュール
// ============================================================================
// 学習目的：
//   - Microsoft.Authorization/roleAssignments の scope と principalId の取り回し
//   - guid(scope, principal, role) による冪等な role assignment 名生成
//   - 組み込みロールの role definition GUID（unique across tenants）
//
// Bicep の roleAssignment は scope が静的に解決できる必要があるため、
// scope（Storage / Key Vault / Azure OpenAI）ごとにループを分けて宣言している。

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

// 組み込みロール定義 ID（Azure グローバル定数）。
var roleIds = {
  storageBlobDataOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  storageQueueDataContributor: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  storageTableDataContributor: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  storageFileDataSmbShareContributor: '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb'
  cognitiveServicesOpenAiUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
}

// ----------------------------------------------------------------------------
// 割り当て一覧（scope 別）
//   - storageRoles: Function App MI が AzureWebJobsStorage の identity-based connection で必要とする 4 ロール
//   - keyVaultRoles: Function App / APIM の MI が backend-shared-secret を読むためのロール
//   - aoaiRoles: APIM MI が disableLocalAuth=true の AOAI を呼ぶための token 認証用ロール
// ----------------------------------------------------------------------------
var storageRoles = [
  { principalId: functionAppPrincipalId, roleId: roleIds.storageBlobDataOwner }
  { principalId: functionAppPrincipalId, roleId: roleIds.storageQueueDataContributor }
  { principalId: functionAppPrincipalId, roleId: roleIds.storageTableDataContributor }
  { principalId: functionAppPrincipalId, roleId: roleIds.storageFileDataSmbShareContributor }
]

var keyVaultRoles = [
  { principalId: functionAppPrincipalId, roleId: roleIds.keyVaultSecretsUser }
  { principalId: apimPrincipalId, roleId: roleIds.keyVaultSecretsUser }
]

var aoaiRoles = enableAzureOpenAiApi
  ? [
      { principalId: apimPrincipalId, roleId: roleIds.cognitiveServicesOpenAiUser }
    ]
  : []

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource azureOpenAiAccount 'Microsoft.CognitiveServices/accounts@2025-12-01' existing = if (enableAzureOpenAiApi) {
  name: azureOpenAiAccountName
}

resource storageRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for role in storageRoles: {
  scope: storageAccount
  name: guid(storageAccount.id, role.principalId, role.roleId)
  properties: {
    principalId: role.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.roleId)
  }
}]

resource keyVaultRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for role in keyVaultRoles: {
  scope: keyVault
  name: guid(keyVault.id, role.principalId, role.roleId)
  properties: {
    principalId: role.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.roleId)
  }
}]

resource aoaiRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for role in aoaiRoles: {
  scope: azureOpenAiAccount
  name: guid(resourceId('Microsoft.CognitiveServices/accounts', azureOpenAiAccountName), role.principalId, role.roleId)
  properties: {
    principalId: role.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.roleId)
  }
}]
