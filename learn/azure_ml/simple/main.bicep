// ============================================================================
// Azure Machine Learning ハンズオン基盤 (記事 azure_ml.md の Bicep 実装)
// ============================================================================
// 記事 1〜2 章の「Workspace を中心に、付随リソース (Storage / Key Vault /
// Application Insights) がぶら下がる」構図を、宣言的な Bicep に置き換えたもの。
// Compute / Environment / Data / Job / Model / Endpoint (記事 4〜9 章) は
// インフラではなく Workspace 配下の概念なので、Python SDK v2 (flow/) 側で扱う。
//
// Container Registry はここでは作らない。記事 2 章の注記どおり、初回の
// Environment ビルド時に Azure ML が自動作成する。
//
// デプロイコマンド:
//   az deployment group create \
//     --resource-group rg-aml-demo \
//     --template-file main.bicep \
//     --parameters main.bicepparam

// ============================================================================
// パラメータ
// ============================================================================

@description('Azure リソースをデプロイするリージョン')
param location string = resourceGroup().location

@description('リソース名のプレフィックス')
@minLength(2)
@maxLength(10)
param prefix string = 'amldemo'

@description('一意性を確保するためのサフィックス')
param suffix string = uniqueString(resourceGroup().id)

@description('リソースに適用するタグ')
param tags object = {
  Environment: 'Development'
  Project: 'AzureMlHandsOn'
  ManagedBy: 'Bicep'
}

// ============================================================================
// 名前 (Storage は英小数字のみ・グローバル一意、Key Vault は 24 文字以内)
// ============================================================================
var names = {
  storage: take(toLower('st${replace(prefix, '-', '')}${suffix}'), 24)
  keyVault: take('kv-${prefix}-${suffix}', 24)
  logAnalytics: 'log-${prefix}-${suffix}'
  appInsights: 'appi-${prefix}-${suffix}'
  workspace: 'mlw-${prefix}'
}

// ============================================================================
// 付随リソース (記事 2 章)
// ============================================================================
module storage './modules/storage.bicep' = {
  name: 'storage'
  params: {
    location: location
    storageName: names.storage
    tags: tags
  }
}

module keyvault './modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    keyVaultName: names.keyVault
    tags: tags
  }
}

module monitoring './modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    logAnalyticsName: names.logAnalytics
    appInsightsName: names.appInsights
    tags: tags
  }
}

// ============================================================================
// Workspace 本体 (記事 1 章。付随リソースを束ねる中心)
// ============================================================================
module workspace './modules/workspace.bicep' = {
  name: 'workspace'
  params: {
    location: location
    workspaceName: names.workspace
    storageId: storage.outputs.storageId
    keyVaultId: keyvault.outputs.keyVaultId
    appInsightsId: monitoring.outputs.appInsightsId
    tags: tags
  }
}

// ============================================================================
// 出力 (justfile の write-config が SDK 用 config.json を組み立てるのに使う)
// ============================================================================
@description('サブスクリプション ID (MLClient / config.json に使う)')
output subscriptionId string = subscription().subscriptionId

@description('リソースグループ名 (MLClient / config.json に使う)')
output resourceGroupName string = resourceGroup().name

@description('Workspace 名 (MLClient / config.json に使う)')
output workspaceName string = workspace.outputs.workspaceName
