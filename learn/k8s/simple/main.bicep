// ============================================================================
// AKS が主役の最小構成アプリ基盤 (記事 aks_app_build.md の Bicep 実装)
// ============================================================================
// 記事では az CLI のコマンド列で組んでいた以下のインフラを、宣言的な Bicep に
// 置き換えたもの。K8s マニフェスト本体 (Deployment / Service / Ingress / HPA /
// Secret) は manifests/ に分離し、justfile から kubectl で適用する。
//
//   - Azure Container Registry (ACR)           … イメージの置き場所
//   - AKS クラスタ (+ application routing addon) … 望ましい状態を維持する基盤
//   - ACR への AcrPull ロール付与               … 記事の --attach-acr 相当
//   - Azure Database for PostgreSQL フレキシブル … ステートフルを外へ逃がす
//
// デプロイコマンド:
//   az deployment group create \
//     --resource-group rg-aks-demo \
//     --template-file main.bicep \
//     --parameters main.bicepparam

// ============================================================================
// パラメータ
// ============================================================================

@description('Azure リソースをデプロイするリージョン')
param location string = resourceGroup().location

@description('リソース名のプレフィックス')
@minLength(1)
@maxLength(12)
param prefix string = 'aksdemo'

@description('一意性を確保するためのサフィックス')
param suffix string = uniqueString(resourceGroup().id)

@description('AKS のノード数')
@minValue(1)
param nodeCount int = 2

@description('AKS ノードの VM サイズ')
param nodeVmSize string = 'Standard_DS2_v2'

@description('Kubernetes バージョン。空文字なら AKS の既定バージョンを使う')
param kubernetesVersion string = ''

@description('PostgreSQL 管理者ユーザー名')
param pgAdminUser string = 'pgadmin'

@description('PostgreSQL 管理者パスワード')
@secure()
@minLength(8)
param pgAdminPassword string

@description('PostgreSQL のメジャーバージョン')
@allowed(['14', '15', '16'])
param pgVersion string = '16'

@description('リソースに適用するタグ')
param tags object = {
  Environment: 'Development'
  Project: 'AksAppBuild'
  ManagedBy: 'Bicep'
}

// ============================================================================
// 名前 (ACR は英数字のみ・グローバル一意、PG は小文字英数字とハイフン)
// ============================================================================
var resourceNames = {
  acr: take(toLower('acr${prefix}${suffix}'), 50)
  aks: 'aks-${prefix}'
  pg: take(toLower('pg-${prefix}-${suffix}'), 63)
}

// ============================================================================
// モジュール
// ============================================================================
module acr './modules/acr.bicep' = {
  name: 'acrResources'
  params: {
    location: location
    acrName: resourceNames.acr
    tags: tags
  }
}

module aks './modules/aks.bicep' = {
  name: 'aksResources'
  params: {
    location: location
    aksName: resourceNames.aks
    nodeCount: nodeCount
    nodeVmSize: nodeVmSize
    kubernetesVersion: kubernetesVersion
    tags: tags
  }
}

// 記事の `--attach-acr` 相当: AKS の kubelet マネージド ID に AcrPull を付与する。
// これにより imagePullSecret なしで ACR から pull できる。
module acrRole './modules/acr-role.bicep' = {
  name: 'acrPullRole'
  params: {
    acrName: acr.outputs.acrName
    kubeletObjectId: aks.outputs.kubeletObjectId
  }
}

module postgres './modules/postgres.bicep' = {
  name: 'postgresResources'
  params: {
    location: location
    pgName: resourceNames.pg
    adminUser: pgAdminUser
    adminPassword: pgAdminPassword
    pgVersion: pgVersion
    tags: tags
  }
}

// ============================================================================
// 出力 (justfile が各レシピで参照する)
// ============================================================================
@description('ACR 名 (az acr build の --registry に使う)')
output acrName string = acr.outputs.acrName

@description('ACR ログインサーバ (マニフェストの image: に使う)')
output acrLoginServer string = acr.outputs.acrLoginServer

@description('AKS クラスタ名 (az aks get-credentials に使う)')
output aksName string = aks.outputs.aksName

@description('PostgreSQL の FQDN (Secret の PGHOST に使う)')
output pgFqdn string = postgres.outputs.pgFqdn

@description('PostgreSQL 管理者ユーザー名 (Secret の PGUSER に使う)')
output pgAdminUser string = pgAdminUser
