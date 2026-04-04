@description('API Management サービス名')
param apimServiceName string

@description('Azure OpenAI リソースのエンドポイント。例: https://example.openai.azure.com')
param azureOpenAiEndpoint string

@description('AOAI バックエンドの API キーを格納した named value 名')
param azureOpenAiApiKeyNamedValueName string = 'azure-openai-api-key'

@description('Azure OpenAI API 名')
param azureOpenAiApiName string = 'azure-openai-api'

@description('Azure OpenAI API の公開パス')
param azureOpenAiApiPath string = 'aoai'

@description('Azure OpenAI API を束ねる Product 名')
param azureOpenAiProductName string = 'azure-openai-product'

@description('Azure OpenAI API 用の既定 Subscription 名')
param azureOpenAiSubscriptionName string = 'azure-openai-default-subscription'

// APIM の backend serviceUrl には /openai 付きのベース URL を渡す。
var azureOpenAiServiceUrl = '${azureOpenAiEndpoint}/openai'

// クライアントから AOAI の秘密情報は見せず、APIM が named value を使って中継する。
var azureOpenAiPolicyXml = '<policies><inbound><base /><set-header name="api-key" exists-action="override"><value>{{${azureOpenAiApiKeyNamedValueName}}}</value></set-header></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'

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

resource apiManagement 'Microsoft.ApiManagement/service@2022-08-01' existing = {
  name: apimServiceName
}

resource azureOpenAiApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
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

resource azureOpenAiOperationsResource 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' = [for operation in azureOpenAiOperations: {
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

resource azureOpenAiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2022-08-01' = {
  parent: azureOpenAiApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: azureOpenAiPolicyXml
  }
  dependsOn: [
    azureOpenAiOperationsResource
  ]
}

resource azureOpenAiProduct 'Microsoft.ApiManagement/service/products@2022-08-01' = {
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

resource azureOpenAiProductApi 'Microsoft.ApiManagement/service/products/apis@2022-08-01' = {
  parent: azureOpenAiProduct
  name: azureOpenAiApi.name
}

resource azureOpenAiSubscription 'Microsoft.ApiManagement/service/subscriptions@2022-08-01' = {
  parent: apiManagement
  name: azureOpenAiSubscriptionName
  properties: {
    allowTracing: false
    displayName: 'Default Azure OpenAI subscription'
    scope: azureOpenAiProduct.id
    state: 'active'
  }
}

output azureOpenAiApiBaseUrl string = 'https://${apiManagement.name}.azure-api.net/${azureOpenAiApiPath}'
output subscriptionName string = azureOpenAiSubscription.name
