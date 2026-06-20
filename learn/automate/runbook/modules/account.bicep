// ============================================================================
// Azure Automation の「土台」一式
// ============================================================================
//   - Automation Account            … runbook を保持し、ジョブを走らせる入れ物
//                                       system-assigned マネージド ID を有効化する
//   - ロール割り当て (RG スコープ)    … その ID に Reader と Virtual Machine Contributor を付与
//       * Reader               : VM の電源状態を「読む」のに必要
//       * Virtual Machine Contributor : VM を「Start/Stop する」のに必要
//   - Automation 変数 (共有アセット) … コードの外に置く設定。スケジュール実行が参照する
//       * DefaultAction / TargetVMName / TargetVMResourceGroup
//
// runbook 本体・スケジュールは runbook.bicep に分離している。ここは周辺に徹する。

@description('デプロイ先リージョン')
param location string

@description('Automation Account 名')
param automationAccountName string

@description('操作対象 VM の既定名 (Automation 変数の初期値)')
param targetVMName string

@description('操作対象 VM のリソースグループ (Automation 変数の初期値)')
param targetVMResourceGroup string

@description('スケジュール実行時の既定アクション (Start / Stop)')
param defaultAction string

@description('リソースに付けるタグ')
param tags object

// ----------------------------------------------------------------------------
// Automation Account (system-assigned マネージド ID 付き)
// ----------------------------------------------------------------------------
resource account 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: tags
  // この identity が runbook の中で Connect-AzAccount -Identity のサインイン先になる。
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    publicNetworkAccess: true
  }
}

// ----------------------------------------------------------------------------
// Automation 変数 (共有アセット)
//   value は JSON としてエンコードする必要がある。文字列なら前後にダブルクオートを付け、
//   '"Stop"' のような「クオート込みの文字列」を渡す (ここが Automation 変数のハマりどころ)。
// ----------------------------------------------------------------------------
resource varAction 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: account
  name: 'DefaultAction'
  properties: {
    value: '"${defaultAction}"'
    isEncrypted: false
    description: 'スケジュール実行時に runbook が使う既定アクション'
  }
}

resource varVMName 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: account
  name: 'TargetVMName'
  properties: {
    value: '"${targetVMName}"'
    isEncrypted: false
    description: '操作対象 VM 名'
  }
}

resource varVMRg 'Microsoft.Automation/automationAccounts/variables@2023-11-01' = {
  parent: account
  name: 'TargetVMResourceGroup'
  properties: {
    value: '"${targetVMResourceGroup}"'
    isEncrypted: false
    description: '操作対象 VM のリソースグループ'
  }
}

// ----------------------------------------------------------------------------
// ロール割り当て (リソースグループ スコープ)
//   組み込みロールの固定 GUID を使う。principalId は account の system-assigned ID。
// ----------------------------------------------------------------------------
var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
var vmContributorRoleId = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c' // Virtual Machine Contributor

resource readerAssign 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, account.id, readerRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: account.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource vmContribAssign 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, account.id, vmContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmContributorRoleId)
    principalId: account.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output automationAccountName string = account.name
output automationAccountId string = account.id
output principalId string = account.identity.principalId
