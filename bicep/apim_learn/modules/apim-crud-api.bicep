@description('API Management サービス名')
param apimServiceName string

@description('Function App のデフォルトホスト名')
param functionDefaultHostName string

@description('CRUD API 名')
param crudApiName string = 'crud-api'

@description('CRUD API の公開パス')
param crudApiPath string = 'crud'

@description('CRUD API を束ねる Product 名')
param crudProductName string = 'crud-product'

@description('CRUD API 用の既定 Subscription 名')
param crudSubscriptionName string = 'crud-default-subscription'

@description('CRUD バックエンド認証シークレットを格納した named value 名')
param backendSecretNamedValueName string = 'function-backend-secret'

// operation 定義はデータなので JSON で外出し。APIM の MCP export がツール情報として
// 操作名・説明・パラメータ・リクエスト例を使うため、LLM エージェント向けにも分かりやすい記述を入れている。
var crudOperations = loadJsonContent('./crud-api.operations.json')

// policy XML は別ファイル。named value 名はテンプレ部分を replace で差し込む。
var crudPolicyXml = replace(loadTextContent('./crud-api.policy.xml'), '__BACKEND_SECRET_NAMED_VALUE__', backendSecretNamedValueName)

var crudApiServiceUrl = 'https://${functionDefaultHostName}/api'

resource apiManagement 'Microsoft.ApiManagement/service@2022-08-01' existing = {
  name: apimServiceName
}

resource crudApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
  parent: apiManagement
  name: crudApiName
  properties: {
    displayName: 'CRUD API'
    description: 'Azure Functions CRUD sample protected by APIM subscription key.'
    path: crudApiPath
    protocols: ['https']
    serviceUrl: crudApiServiceUrl
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'X-API-Key'
      query: 'api-key'
    }
    apiType: 'http'
    type: 'http'
  }
}

resource crudOperationsResource 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' = [for operation in crudOperations: {
  parent: crudApi
  name: operation.name
  properties: {
    displayName: operation.displayName
    method: operation.method
    urlTemplate: operation.urlTemplate
    description: operation.description
    request: operation.request
    templateParameters: operation.templateParameters
    responses: operation.responses
  }
}]

resource crudApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2022-08-01' = {
  parent: crudApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: crudPolicyXml
  }
  dependsOn: [crudOperationsResource]
}

resource crudProduct 'Microsoft.ApiManagement/service/products@2022-08-01' = {
  parent: apiManagement
  name: crudProductName
  properties: {
    displayName: 'CRUD Product'
    description: 'Subscription-protected access to the CRUD sample API.'
    state: 'published'
    subscriptionRequired: true
    terms: 'Use for sample and learning purposes.'
  }
}

resource crudProductApi 'Microsoft.ApiManagement/service/products/apis@2022-08-01' = {
  parent: crudProduct
  name: crudApi.name
}

resource crudSubscription 'Microsoft.ApiManagement/service/subscriptions@2022-08-01' = {
  parent: apiManagement
  name: crudSubscriptionName
  properties: {
    allowTracing: false
    displayName: 'Default CRUD subscription'
    scope: crudProduct.id
    state: 'active'
  }
}

output apiBaseUrl string = 'https://${apiManagement.name}.azure-api.net/${crudApiPath}'
output subscriptionName string = crudSubscription.name
