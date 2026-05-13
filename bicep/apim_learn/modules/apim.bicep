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

// API 名・パス・Product 名・Subscription 名は学習サンプル用の固定値。
// 上書きが必要なケースは現状ないので param ではなく var に置く。
var apiNames = {
  crud: {
    api: 'crud-api'
    path: 'crud'
    product: 'crud-product'
    subscription: 'crud-default-subscription'
  }
  aoai: {
    api: 'azure-openai-api'
    path: 'aoai'
    product: 'azure-openai-product'
    subscription: 'azure-openai-default-subscription'
  }
}

var apimBackendSecretNamedValueName = 'function-backend-secret'

// Consumption は capacity=0 固定、それ以外は 1 ユニット。
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
    tags: ['backend', 'function']
  }
}

module crudApi './apim-crud-api.bicep' = {
  name: 'apimCrudApiResources'
  params: {
    apimServiceName: apiManagement.name
    functionDefaultHostName: functionDefaultHostName
    crudApiName: apiNames.crud.api
    crudApiPath: apiNames.crud.path
    crudProductName: apiNames.crud.product
    crudSubscriptionName: apiNames.crud.subscription
    backendSecretNamedValueName: apimBackendSecret.name
  }
}

module azureOpenAiApi './apim-aoai-api.bicep' = if (enableAzureOpenAiApi) {
  name: 'apimAzureOpenAiApiResources'
  params: {
    apimServiceName: apiManagement.name
    azureOpenAiEndpoint: azureOpenAiEndpoint
    azureOpenAiApiName: apiNames.aoai.api
    azureOpenAiApiPath: apiNames.aoai.path
    azureOpenAiProductName: apiNames.aoai.product
    azureOpenAiSubscriptionName: apiNames.aoai.subscription
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
