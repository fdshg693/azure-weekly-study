@description('Azure リソースをデプロイするリージョン')
param location string

@description('API Management サービス名')
param apimServiceName string

@description('API Management の SKU')
param apimSkuName string

@description('API Management の publisher 名')
param apimPublisherName string

@description('API Management の publisher メールアドレス')
param apimPublisherEmail string

@description('Function App のデフォルトホスト名')
param functionDefaultHostName string

@description('リソースに適用するタグ')
param tags object

@description('BACKEND_SHARED_SECRET を保持する Key Vault シークレットの versionless URI')
param backendSecretUri string

@description('Azure OpenAI バックエンドを APIM 配下の別 API として公開するか')
param enableAzureOpenAiApi bool = false

@description('Azure OpenAI リソースのエンドポイント。末尾の / は付けずに指定してください。例: https://example.openai.azure.com')
param azureOpenAiEndpoint string = ''

@description('CRUD API 名')
param crudApiName string = 'crud-api'

@description('CRUD API の公開パス')
param crudApiPath string = 'crud'

@description('CRUD API を束ねる Product 名')
param crudProductName string = 'crud-product'

@description('CRUD API 用の既定 Subscription 名')
param crudSubscriptionName string = 'crud-default-subscription'

@description('CRUD バックエンド認証シークレットを保持する named value 名')
param apimBackendSecretNamedValueName string = 'function-backend-secret'

@description('Azure OpenAI API 名')
param azureOpenAiApiName string = 'azure-openai-api'

@description('Azure OpenAI API の公開パス')
param azureOpenAiApiPath string = 'aoai'

@description('Azure OpenAI API を束ねる Product 名')
param azureOpenAiProductName string = 'azure-openai-product'

@description('Azure OpenAI API 用の既定 Subscription 名')
param azureOpenAiSubscriptionName string = 'azure-openai-default-subscription'

var apimSkuCapacity = apimSkuName == 'Consumption' ? 0 : 1

// APIM は System-Assigned Managed Identity を使って Key Vault からシークレットを取得し、
// AOAI バックエンドをトークン認証で呼ぶ。
resource apiManagement 'Microsoft.ApiManagement/service@2022-08-01' = {
  name: apimServiceName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: apimSkuName
    capacity: apimSkuCapacity
  }
  properties: {
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    publicNetworkAccess: 'Enabled'
    virtualNetworkType: 'None'
  }
  tags: tags
}

// CRUD バックエンド呼び出し時に APIM が付与する内部認証ヘッダー値は Key Vault から動的に取得する。
// versionless URI なので Key Vault 側でシークレットをローテートすれば APIM 側も自動で追従する。
resource apimBackendSecret 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  parent: apiManagement
  name: apimBackendSecretNamedValueName
  properties: {
    displayName: apimBackendSecretNamedValueName
    secret: true
    keyVault: {
      secretIdentifier: backendSecretUri
    }
    tags: [
      'backend'
      'function'
    ]
  }
}

module crudApi './apim-crud-api.bicep' = {
  name: 'apimCrudApiResources'
  params: {
    apimServiceName: apiManagement.name
    functionDefaultHostName: functionDefaultHostName
    crudApiName: crudApiName
    crudApiPath: crudApiPath
    crudProductName: crudProductName
    crudSubscriptionName: crudSubscriptionName
    backendSecretNamedValueName: apimBackendSecret.name
  }
}

module azureOpenAiApi './apim-aoai-api.bicep' = if (enableAzureOpenAiApi) {
  name: 'apimAzureOpenAiApiResources'
  params: {
    apimServiceName: apiManagement.name
    azureOpenAiEndpoint: azureOpenAiEndpoint
    azureOpenAiApiName: azureOpenAiApiName
    azureOpenAiApiPath: azureOpenAiApiPath
    azureOpenAiProductName: azureOpenAiProductName
    azureOpenAiSubscriptionName: azureOpenAiSubscriptionName
  }
}

output apimServiceName string = apiManagement.name
output apimGatewayUrl string = 'https://${apiManagement.name}.azure-api.net'
output apimPrincipalId string = apiManagement.identity.principalId
output apiBaseUrl string = crudApi.outputs.apiBaseUrl
output apiKeyHeaderName string = 'X-API-Key'
output apimSubscriptionName string = crudApi.outputs.subscriptionName
output azureOpenAiApiBaseUrl string = enableAzureOpenAiApi ? azureOpenAiApi!.outputs.azureOpenAiApiBaseUrl : ''
output azureOpenAiApimSubscriptionName string = enableAzureOpenAiApi ? azureOpenAiApi!.outputs.subscriptionName : ''
