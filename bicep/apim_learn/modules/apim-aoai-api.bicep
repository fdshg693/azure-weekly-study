@description('API Management サービス名')
param apimServiceName string

@description('Azure OpenAI リソースのエンドポイント。例: https://example.openai.azure.com')
param azureOpenAiEndpoint string

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

// APIM の System-Assigned Managed Identity で AOAI を呼ぶ。AOAI 側で disableLocalAuth:true としているため key 認証は不可。
// authentication-managed-identity は Entra から取得したトークンを Authorization: Bearer に付与する。
var azureOpenAiPolicyXml = loadTextContent('./aoai-api.policy.xml')

var azureOpenAiOperations = loadJsonContent('./aoai-api.operations.json')

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
    protocols: ['https']
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
  dependsOn: [azureOpenAiOperationsResource]
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
