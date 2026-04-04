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

@secure()
@description('APIM から Function App へ送るバックエンド認証シークレット')
param backendSharedSecret string

@description('Azure OpenAI バックエンドを APIM 配下の別 API として公開するか')
param enableAzureOpenAiApi bool = false

@description('Azure OpenAI リソースのエンドポイント。末尾の / は付けずに指定してください。例: https://example.openai.azure.com')
param azureOpenAiEndpoint string = ''

@secure()
@description('Azure OpenAI リソースの API キー')
param azureOpenAiApiKey string = ''

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

@description('AOAI バックエンド API キーを保持する named value 名')
param azureOpenAiApiKeyNamedValueName string = 'azure-openai-api-key'

var apimSkuCapacity = apimSkuName == 'Developer' ? 0 : 1

// このモジュールは APIM 本体と共有シークレットだけを管理する。
// 各 API の詳細定義は子モジュールに分割し、読みやすさを優先する。
resource apiManagement 'Microsoft.ApiManagement/service@2022-08-01' = {
  name: apimServiceName
  location: location
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

// CRUD バックエンド呼び出し時に APIM が付与する内部認証ヘッダー値を保存する。
resource apimBackendSecret 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  parent: apiManagement
  name: apimBackendSecretNamedValueName
  properties: {
    displayName: apimBackendSecretNamedValueName
    secret: true
    value: backendSharedSecret
    tags: [
      'backend'
      'function'
    ]
  }
}

// AOAI の API キーは APIM 内の named value に格納し、policy から参照する。
resource azureOpenAiBackendKey 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = if (enableAzureOpenAiApi) {
  parent: apiManagement
  name: azureOpenAiApiKeyNamedValueName
  properties: {
    displayName: azureOpenAiApiKeyNamedValueName
    secret: true
    value: azureOpenAiApiKey
    tags: [
      'backend'
      'azure-openai'
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
    azureOpenAiApiKeyNamedValueName: azureOpenAiBackendKey.name
  }
}

output apimServiceName string = apiManagement.name
output apimGatewayUrl string = 'https://${apiManagement.name}.azure-api.net'
output apiBaseUrl string = crudApi.outputs.apiBaseUrl
output apiKeyHeaderName string = 'X-API-Key'
output apimSubscriptionName string = crudApi.outputs.subscriptionName
output azureOpenAiApiBaseUrl string = enableAzureOpenAiApi ? azureOpenAiApi!.outputs.azureOpenAiApiBaseUrl : ''
output azureOpenAiApimSubscriptionName string = enableAzureOpenAiApi ? azureOpenAiApi!.outputs.subscriptionName : ''
