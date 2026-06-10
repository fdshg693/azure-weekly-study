@description('Storage Account 名')
param storageAccountName string

@description('対象 VM 名')
param vmName string

@description('Function App の System-Assigned MI の Principal ID')
param functionAppPrincipalId string

// Built-in role definition IDs (GUIDs)
var roleIds = {
  // Storage
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  storageTableDataContributor: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  storageQueueDataContributor: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  storageFileSmbShareContributor: '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb'
  // VM 操作 (start / deallocate / runCommand)
  virtualMachineContributor: '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' existing = {
  name: vmName
}

// ----------------------------------------------------------------------------
// Function MI → Storage (AzureWebJobsStorage 用)
// ----------------------------------------------------------------------------
resource roleStorageBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, functionAppPrincipalId, roleIds.storageBlobDataContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.storageBlobDataContributor)
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource roleStorageTable 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, functionAppPrincipalId, roleIds.storageTableDataContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.storageTableDataContributor)
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource roleStorageQueue 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, functionAppPrincipalId, roleIds.storageQueueDataContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.storageQueueDataContributor)
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource roleStorageFile 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, functionAppPrincipalId, roleIds.storageFileSmbShareContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.storageFileSmbShareContributor)
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ----------------------------------------------------------------------------
// Function MI → VM (start / deallocate / runCommand)
// ----------------------------------------------------------------------------
resource roleVm 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vm
  name: guid(vm.id, functionAppPrincipalId, roleIds.virtualMachineContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.virtualMachineContributor)
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}
