// このプロジェクトの新規 Bicep は「キーレス化の核」だけに絞る:
//   User-Assigned Managed Identity (UAMI) + Federated Identity Credential (FIC)。
//
// AKS の OIDC/Workload Identity 有効化、PostgreSQL の Entra 認証有効化、
// UAMI を PG の Entra 管理者にする操作は、いずれも simple で作った既存リソースへの
// 「その場更新」や実験で頻繁に付け外しするため、Bicep ではなく az スクリプト側に置く
// (scripts/infra-prep.ps1 / pg-entra.ps1 / role-on.ps1 / role-off.ps1)。
//
// FIC の issuer には、先に有効化した AKS の OIDC issuer URL を渡す。
// subject は「どの ServiceAccount を信頼するか」= system:serviceaccount:<ns>:<sa>。

@description('リソースをデプロイするリージョン')
param location string = resourceGroup().location

@description('作成する User-Assigned Managed Identity 名 (PG ログインユーザー名にもなる)')
param uamiName string = 'id-aks-pg-workload'

@description('AKS の OIDC issuer URL (infra-prep で有効化した後の値を渡す)')
param oidcIssuerUrl string

@description('Pod を動かす名前空間')
param namespace string = 'workload-identity'

@description('信頼する ServiceAccount 名')
param serviceAccountName string = 'pg-accessor'

@description('リソースに適用するタグ')
param tags object = {
  project: 'k8s-workload-identity'
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
  tags: tags
}

// Federated Identity Credential:
// 「issuer (= AKS の OIDC) が発行した、subject (= この SA) のトークン」を
// この UAMI のトークンに交換することを許可する設定。これが Workload Identity の心臓部。
resource fic 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: uami
  name: 'aks-pg-accessor'
  properties: {
    issuer: oidcIssuerUrl
    subject: 'system:serviceaccount:${namespace}:${serviceAccountName}'
    // Azure AD のトークン交換で使う固定のオーディエンス。
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// apply / role-* スクリプトが使う値。clientId は SA の注釈に、
// principalId は PG の Entra 管理者登録 (object-id) に使う。
output uamiClientId string = uami.properties.clientId
output uamiPrincipalId string = uami.properties.principalId
output uamiName string = uami.name
