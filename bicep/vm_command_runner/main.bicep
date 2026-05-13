// ============================================================================
// シンプル VM コマンドランナー
// ============================================================================
// Function App (HTTP Trigger) でホワイトリスト済みコマンドを受け取り、
// Azure VM Run Command 経由で VM 上で実行する。
// アイドル時は Timer Trigger が VM を deallocate (課金停止) する。
// 停止中に HTTP が来た場合は 202 を返し、バックグラウンドで起動を試みる。
//
// セキュリティモデル：
//   - Function App は System-Assigned Managed Identity で VM / Storage にアクセス
//   - VM へ SSH ポートは開けず、Azure Run Command 拡張のみで操作
//   - コマンドは Function 側ホワイトリストでのみ許可
//
// デプロイコマンド:
//   az deployment group create \
//     --resource-group <リソースグループ名> \
//     --template-file main.bicep \
//     --parameters main.bicepparam

// ============================================================================
// パラメータ
// ============================================================================

@description('Azure リソースをデプロイするリージョン')
param location string = resourceGroup().location

@description('リソース名のプレフィックス（グローバルで一意になるよう調整してください）')
@minLength(1)
param prefix string = 'vmcmd'

@description('一意性を確保するためのサフィックス')
param suffix string = uniqueString(resourceGroup().id)

@description('Python ランタイムのバージョン')
@allowed(['3.10', '3.11', '3.12'])
param pythonVersion string = '3.11'

@description('App Service Plan の SKU。Identity-based AzureWebJobsStorage は Premium (EP*) 以上が必要。')
@allowed(['EP1', 'EP2', 'EP3'])
param servicePlanSku string = 'EP1'

@description('VM のサイズ')
param vmSize string = 'Standard_B1s'

@description('VM の管理者ユーザー名 (SSH ポートは開けないが、OS 上のユーザーとして必要)')
param vmAdminUsername string = 'azureuser'

@description('VM の管理者 SSH 公開鍵。SSH は到達不可だが Azure 仕様上必須。')
@secure()
param vmAdminSshPublicKey string

@description('アイドル何分でVMを deallocate するか')
@minValue(2)
param idleMinutesBeforeStop int = 10

@description('リソースに適用するタグ')
param tags object = {
  Environment: 'Development'
  Project: 'VmCommandRunner'
  ManagedBy: 'Bicep'
}

// ============================================================================
// 名前
// ============================================================================
var resourceNames = {
  functionApp: 'func-${prefix}-${suffix}'
  storage: take(toLower('st${prefix}${suffix}'), 24)
  vm: 'vm-${prefix}-${take(suffix, 8)}'
  vnet: 'vnet-${prefix}-${take(suffix, 8)}'
  servicePlan: 'plan-${prefix}-${take(suffix, 8)}'
}

// ============================================================================
// モジュール
// ============================================================================
module storage './modules/storage.bicep' = {
  name: 'storageResources'
  params: {
    location: location
    storageAccountName: resourceNames.storage
    tags: tags
  }
}

module servicePlan './modules/service-plan.bicep' = {
  name: 'servicePlanResources'
  params: {
    location: location
    servicePlanName: resourceNames.servicePlan
    servicePlanSku: servicePlanSku
    tags: tags
  }
}

module vm './modules/vm.bicep' = {
  name: 'vmResources'
  params: {
    location: location
    vmName: resourceNames.vm
    vnetName: resourceNames.vnet
    vmSize: vmSize
    adminUsername: vmAdminUsername
    adminSshPublicKey: vmAdminSshPublicKey
    tags: tags
  }
}

module functionApp './modules/function-app.bicep' = {
  name: 'functionAppResources'
  params: {
    location: location
    functionAppName: resourceNames.functionApp
    servicePlanId: servicePlan.outputs.servicePlanId
    storageAccountName: storage.outputs.storageAccountName
    pythonVersion: pythonVersion
    tags: tags
    targetVmResourceId: vm.outputs.vmResourceId
    targetVmName: vm.outputs.vmName
    targetVmResourceGroup: resourceGroup().name
    idleMinutesBeforeStop: idleMinutesBeforeStop
  }
}

module roleAssignments './modules/role-assignments.bicep' = {
  name: 'roleAssignments'
  params: {
    storageAccountName: storage.outputs.storageAccountName
    vmName: vm.outputs.vmName
    functionAppPrincipalId: functionApp.outputs.functionAppPrincipalId
  }
}

// ============================================================================
// 出力
// ============================================================================
@description('Function App 名')
output functionAppName string = functionApp.outputs.functionAppName

@description('Function App URL')
output functionAppUrl string = functionApp.outputs.functionAppUrl

@description('対象 VM 名')
output targetVmName string = vm.outputs.vmName

@description('Storage Account 名')
output storageAccountName string = storage.outputs.storageAccountName

@description('Function コードを手動デプロイするコマンド')
output deployCommand string = 'cd python && func azure functionapp publish ${functionApp.outputs.functionAppName}'
