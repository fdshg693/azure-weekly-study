// ============================================================================
// container/registry — Azure Container Registry (ACR) が主役の最小プロジェクト
// ============================================================================
// container トピックの「土台」。後続ステップ (aci / webapp-container / container-apps)
// は、ここに上げたイメージを各サービスが pull する前提なので、最初に固める。
//
// このファイルで作るもの:
//   - Azure Container Registry (ACR)      … クラウドのイメージ置き場 + クラウドビルド(ACR Tasks)
//   - User-Assigned Managed Identity      … 後続サービスが「キーレス pull」に使う ID
//   - AcrPull ロール付与 (ACR スコープ)    … その ID に pull 権限を与える
//
// デプロイ:
//   az deployment group create \
//     --resource-group rg-container-registry \
//     --template-file main.bicep --parameters main.bicepparam
//
// 設計メモ:
//   - admin user は既定で無効 (adminUserEnabled=false)。pull/push は Entra の
//     トークン認証 (`az acr login`) + RBAC で行う＝キーレスを第一選択にする。
//     admin user は「共有パスワードのアンチパターン」を体感する対比用にだけ有効化する。
//   - UAMI + AcrPull は「後続サービスが使う消費者 ID」の土台。UAMI はマネージド ID ゆえ
//     手元から使えない (IMDS 経由) ので、Step 1 では AcrPull を付けた土台を用意するに留め、
//     UAMI 本人による pull / AcrPull を外した 403 体感は Step 2 (aci) で行使する。
//     ※AcrPull の因果をローカルで観測する実験は SP を代役にした `task acrpull-demo` で行う。

@description('デプロイ先リージョン')
param location string = resourceGroup().location

@description('リソース名のプレフィックス (英数字)')
@minLength(1)
@maxLength(10)
param prefix string = 'reg'

@description('一意性確保用サフィックス (既定は RG ID 由来)')
@minLength(2)
param suffix string = uniqueString(resourceGroup().id)

@description('ACR の SKU。Basic で十分 (Premium は geo レプリケーション等)')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Basic'

@description('admin user (共有パスワード) を有効にするか。既定は無効＝キーレス。')
param adminUserEnabled bool = false

@description('リソースに付けるタグ')
param tags object = {
  Environment: 'Development'
  Project: 'ContainerRegistry'
  ManagedBy: 'Bicep'
}

// ACR 名はグローバル一意・英数字のみ・5〜50 文字。
var acrName = take(toLower('acr${prefix}${suffix}'), 50)
var uamiName = 'uami-${prefix}-pull'

// ----------------------------------------------------------------------------
// Azure Container Registry
// ----------------------------------------------------------------------------
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: { name: acrSku }
  properties: {
    // 既定は false (キーレス)。task admin-on で true に切り替えて対比する。
    adminUserEnabled: adminUserEnabled
  }
}

// ----------------------------------------------------------------------------
// 後続サービス用の「消費者 ID」+ AcrPull (土台)
//   aci / webapp / container-apps はこの UAMI を assign して pull する。
//   UAMI 本人での AcrPull 出し入れ→pull 失敗の体感は Step 2 (aci) で行う。
// ----------------------------------------------------------------------------
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
  tags: tags
}

// AcrPull ロール定義 ID (固定 GUID)
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, uami.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ----------------------------------------------------------------------------
// 出力 (Taskfile / scripts が参照)
// ----------------------------------------------------------------------------
@description('ACR 名 (az acr build / login / repository の --name に使う)')
output acrName string = acr.name

@description('ACR ログインサーバ (例: acrreg....azurecr.io)。イメージ参照の接頭辞')
output acrLoginServer string = acr.properties.loginServer

@description('消費者 UAMI のリソース ID (後続サービスが assign する)')
output uamiResourceId string = uami.id

@description('消費者 UAMI の principalId (AcrPull の付け外し対象)')
output uamiPrincipalId string = uami.properties.principalId

@description('消費者 UAMI の clientId')
output uamiClientId string = uami.properties.clientId
