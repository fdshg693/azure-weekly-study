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

@description('既存の Azure OpenAI を APIM 配下の別 API として公開するか')
param enableAzureOpenAiApi bool = false

@description('既存 Azure OpenAI リソースのエンドポイント。末尾の / は付けずに指定してください。例: https://example.openai.azure.com')
param azureOpenAiEndpoint string = ''

@secure()
@description('既存 Azure OpenAI リソースの API キー')
param azureOpenAiApiKey string = ''

param apimApiName string = 'crud-api'
param apimApiPath string = 'crud'
param apimProductName string = 'crud-product'
param apimSubscriptionName string = 'crud-default-subscription'
param apimBackendSecretNamedValueName string = 'function-backend-secret'
param azureOpenAiApiName string = 'azure-openai-api'
param azureOpenAiApiPath string = 'aoai'
param azureOpenAiProductName string = 'azure-openai-product'
param azureOpenAiSubscriptionName string = 'azure-openai-default-subscription'
param azureOpenAiApiKeyNamedValueName string = 'azure-openai-api-key'

var apimSkuCapacity = apimSkuName == 'Developer' ? 0 : 1
var azureOpenAiServiceUrl = empty(azureOpenAiEndpoint) ? '' : '${azureOpenAiEndpoint}/openai'
var apimOperations = [
  {
    name: 'list-items'
    displayName: 'List items'
    method: 'GET'
    urlTemplate: '/items'
    description: 'Get all items.'
    templateParameters: []
  }
  {
    name: 'create-item'
    displayName: 'Create item'
    method: 'POST'
    urlTemplate: '/items'
    description: 'Create a new item.'
    templateParameters: []
  }
  {
    name: 'get-item'
    displayName: 'Get item'
    method: 'GET'
    urlTemplate: '/items/{id}'
    description: 'Get a single item.'
    templateParameters: [
      {
        name: 'id'
        type: 'string'
        required: true
      }
    ]
  }
  {
    name: 'update-item'
    displayName: 'Update item'
    method: 'PUT'
    urlTemplate: '/items/{id}'
    description: 'Update a single item.'
    templateParameters: [
      {
        name: 'id'
        type: 'string'
        required: true
      }
    ]
  }
  {
    name: 'delete-item'
    displayName: 'Delete item'
    method: 'DELETE'
    urlTemplate: '/items/{id}'
    description: 'Delete a single item.'
    templateParameters: [
      {
        name: 'id'
        type: 'string'
        required: true
      }
    ]
  }
]
var azureOpenAiOperations = [
  {
    name: 'chat-completions'
    displayName: 'Chat completions'
    method: 'POST'
    urlTemplate: '/deployments/{deploymentId}/chat/completions'
    description: 'Proxy Azure OpenAI chat completions.'
    templateParameters: [
      {
        name: 'deploymentId'
        type: 'string'
        required: true
      }
    ]
  }
  {
    name: 'embeddings'
    displayName: 'Embeddings'
    method: 'POST'
    urlTemplate: '/deployments/{deploymentId}/embeddings'
    description: 'Proxy Azure OpenAI embeddings.'
    templateParameters: [
      {
        name: 'deploymentId'
        type: 'string'
        required: true
      }
    ]
  }
]

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

resource apimApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
  parent: apiManagement
  name: apimApiName
  properties: {
    displayName: 'CRUD API'
    description: 'Azure Functions CRUD sample protected by APIM subscription key.'
    path: apimApiPath
    protocols: [
      'https'
    ]
    serviceUrl: 'https://${functionDefaultHostName}/api'
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'X-API-Key'
      query: 'api-key'
    }
    apiType: 'http'
    type: 'http'
  }
}

resource apimOperationsResource 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' = [for operation in apimOperations: {
  parent: apimApi
  name: operation.name
  properties: {
    displayName: operation.displayName
    method: operation.method
    urlTemplate: operation.urlTemplate
    description: operation.description
    templateParameters: operation.templateParameters
    responses: []
  }
}]

resource apimApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2022-08-01' = {
  parent: apimApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: '<policies><inbound><base /><set-header name="x-backend-auth" exists-action="override"><value>{{function-backend-secret}}</value></set-header></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
  dependsOn: [
    apimBackendSecret
    apimOperationsResource
  ]
}

resource azureOpenAiApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = if (enableAzureOpenAiApi) {
  parent: apiManagement
  name: azureOpenAiApiName
  properties: {
    displayName: 'Azure OpenAI API'
    description: 'Azure OpenAI backend protected by APIM subscription key.'
    path: azureOpenAiApiPath
    protocols: [
      'https'
    ]
    serviceUrl: azureOpenAiServiceUrl
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'X-API-Key'
      query: 'api-key'
    }
    apiType: 'http'
    type: 'http'
  }
}

resource azureOpenAiOperationsResource 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' = [for operation in azureOpenAiOperations: if (enableAzureOpenAiApi) {
  parent: azureOpenAiApi
  name: operation.name
  properties: {
    displayName: operation.displayName
    method: operation.method
    urlTemplate: operation.urlTemplate
    description: operation.description
    templateParameters: operation.templateParameters
    responses: []
  }
}]

resource azureOpenAiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2022-08-01' = if (enableAzureOpenAiApi) {
  parent: azureOpenAiApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: '<policies><inbound><base /><set-header name="api-key" exists-action="override"><value>{{azure-openai-api-key}}</value></set-header></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
  dependsOn: [
    azureOpenAiBackendKey
    azureOpenAiOperationsResource
  ]
}

resource apimProduct 'Microsoft.ApiManagement/service/products@2022-08-01' = {
  parent: apiManagement
  name: apimProductName
  properties: {
    displayName: 'CRUD Product'
    description: 'Subscription-protected access to the CRUD sample API.'
    state: 'published'
    subscriptionRequired: true
    terms: 'Use for sample and learning purposes.'
  }
}

resource apimProductApi 'Microsoft.ApiManagement/service/products/apis@2022-08-01' = {
  parent: apimProduct
  name: apimApi.name
}

resource apimSubscription 'Microsoft.ApiManagement/service/subscriptions@2022-08-01' = {
  parent: apiManagement
  name: apimSubscriptionName
  properties: {
    allowTracing: false
    displayName: 'Default CRUD subscription'
    scope: apimProduct.id
    state: 'active'
  }
}

resource azureOpenAiProduct 'Microsoft.ApiManagement/service/products@2022-08-01' = if (enableAzureOpenAiApi) {
  parent: apiManagement
  name: azureOpenAiProductName
  properties: {
    displayName: 'Azure OpenAI Product'
    description: 'Subscription-protected access to Azure OpenAI through APIM.'
    state: 'published'
    subscriptionRequired: true
    terms: 'Use according to your Azure OpenAI usage policy.'
  }
}

resource azureOpenAiProductApi 'Microsoft.ApiManagement/service/products/apis@2022-08-01' = if (enableAzureOpenAiApi) {
  parent: azureOpenAiProduct
  name: azureOpenAiApi.name
}

resource azureOpenAiSubscription 'Microsoft.ApiManagement/service/subscriptions@2022-08-01' = if (enableAzureOpenAiApi) {
  parent: apiManagement
  name: azureOpenAiSubscriptionName
  properties: {
    allowTracing: false
    displayName: 'Default Azure OpenAI subscription'
    scope: azureOpenAiProduct.id
    state: 'active'
  }
}

output apimServiceName string = apiManagement.name
output apimGatewayUrl string = 'https://${apiManagement.name}.azure-api.net'
output apiBaseUrl string = 'https://${apiManagement.name}.azure-api.net/${apimApiPath}'
output apiKeyHeaderName string = 'X-API-Key'
output apimSubscriptionName string = apimSubscription.name
output azureOpenAiApiBaseUrl string = enableAzureOpenAiApi ? 'https://${apiManagement.name}.azure-api.net/${azureOpenAiApiPath}' : ''
output azureOpenAiApimSubscriptionName string = enableAzureOpenAiApi ? azureOpenAiSubscription.name : ''
