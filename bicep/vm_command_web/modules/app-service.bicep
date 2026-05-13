@description('リージョン')
param location string

@description('App Service (Web App) 名')
param webAppName string

@description('App Service Plan のリソース ID')
param appServicePlanId string

@description('Node バージョン (ex. 20-lts)')
param nodeVersion string

@description('Function App 名')
param functionAppName string

@description('Function App が存在するリソースグループ名')
param functionAppResourceGroup string

@description('Function 側 Easy Auth で使用する AAD アプリの clientId')
param functionAadClientId string

@description('App Service 側 Easy Auth で使用する AAD アプリの clientId')
param webAadClientId string

@description('Entra テナント ID')
param aadTenantId string

@description('タグ')
param tags object

// Function App URL を生成するために existing 参照
resource functionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: functionAppName
  scope: resourceGroup(functionAppResourceGroup)
}

var functionAppUrl = 'https://${functionApp.properties.defaultHostName}'

// ----------------------------------------------------------------------------
// App Service (Linux + Node)
// ----------------------------------------------------------------------------
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  kind: 'app,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|${nodeVersion}'
      alwaysOn: true
      // adapter-node のビルド成果物のエントリポイント
      appCommandLine: 'node build/index.js'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      appSettings: [
        { name: 'WEBSITE_NODE_DEFAULT_VERSION', value: '~20' }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'false' }
        // SvelteKit が参照するアプリ設定
        { name: 'FUNCTION_APP_URL', value: functionAppUrl }
        { name: 'FUNCTION_AAD_CLIENT_ID', value: functionAadClientId }
        { name: 'ORIGIN', value: 'https://${webAppName}.azurewebsites.net' }
        { name: 'NODE_ENV', value: 'production' }
      ]
    }
  }
  tags: tags
}

// ----------------------------------------------------------------------------
// Easy Auth (Microsoft Entra) — ユーザーログインを必須化
// ----------------------------------------------------------------------------
resource webAuthSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: webApp
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '~2'
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureactivedirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: 'https://sts.windows.net/${aadTenantId}/v2.0'
          clientId: webAadClientId
        }
        login: {
          disableWWWAuthenticate: false
        }
        validation: {
          allowedAudiences: [
            'api://${webAadClientId}'
            webAadClientId
          ]
        }
      }
    }
    login: {
      tokenStore: {
        enabled: true
      }
      preserveUrlFragmentsForLogins: false
    }
  }
}

output name string = webApp.name
output url string = 'https://${webApp.properties.defaultHostName}'
output principalId string = webApp.identity.principalId
