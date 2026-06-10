// 既存 Function App (vm_command_runner) の authsettingsV2 を設定する。
// このモジュールは Function App と同じリソースグループにスコープして呼ばれる前提。

@description('既存 Function App 名')
param functionAppName string

@description('Function 側 Easy Auth で使用する AAD アプリの clientId')
param functionAadClientId string

@description('Entra テナント ID')
param aadTenantId string

@description('許可する呼び出し元 (App Service System-Assigned MI) の Object ID')
param allowedPrincipalObjectId string

resource functionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: functionAppName
}

resource funcAuthSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '~2'
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'Return401'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: 'https://sts.windows.net/${aadTenantId}/v2.0'
          clientId: functionAadClientId
        }
        validation: {
          // 受け入れる audience: App Service が getToken で要求する scope/resource と揃える
          allowedAudiences: [
            'api://${functionAadClientId}'
            functionAadClientId
          ]
          // 呼び出し元 principal を限定 (App Service の MI Object ID のみ)
          defaultAuthorizationPolicy: {
            allowedPrincipals: {
              identities: [
                allowedPrincipalObjectId
              ]
            }
          }
        }
      }
    }
    login: {
      tokenStore: {
        enabled: false
      }
    }
  }
}
