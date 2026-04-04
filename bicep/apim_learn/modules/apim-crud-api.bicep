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

var crudApiServiceUrl = 'https://${functionDefaultHostName}/api'

// Function App の CRUD エンドポイントを APIM の操作として公開する。
var crudOperations = [
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

// named value の実体は親モジュールで作成済みで、policy からだけ参照する。
var crudPolicyXml = '<policies><inbound><base /><set-header name="x-backend-auth" exists-action="override"><value>{{${backendSecretNamedValueName}}}</value></set-header></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'

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
    protocols: [
      'https'
    ]
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
    templateParameters: operation.templateParameters
    responses: []
  }
}]

resource crudApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2022-08-01' = {
  parent: crudApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: crudPolicyXml
  }
  dependsOn: [
    crudOperationsResource
  ]
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
