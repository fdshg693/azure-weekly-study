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
// APIM の MCP export は操作名、説明、パラメータ、リクエスト例をツール情報として利用するため、
// REST API 利用者向けだけでなく LLM エージェント向けにも分かりやすい定義を入れておく。
var crudOperations = [
  {
    name: 'list-items'
    displayName: 'List items'
    method: 'GET'
    urlTemplate: '/items'
    description: 'List all items currently stored in the sample application.'
    templateParameters: []
    request: {
      description: 'No request body is required.'
      headers: []
      queryParameters: []
      representations: []
    }
    responses: [
      {
        statusCode: 200
        description: 'Returns an array of items.'
        representations: [
          {
            contentType: 'application/json'
            examples: {
              sample: {
                summary: 'List items response'
                value: [
                  {
                    id: '11111111-1111-1111-1111-111111111111'
                    name: 'Notebook PC'
                    description: 'Development laptop'
                  }
                ]
              }
            }
          }
        ]
      }
    ]
  }
  {
    name: 'create-item'
    displayName: 'Create item'
    method: 'POST'
    urlTemplate: '/items'
    description: 'Create a new item. The request body must include name and can include description.'
    templateParameters: []
    request: {
      description: 'JSON body for the item to create.'
      headers: []
      queryParameters: []
      representations: [
        {
          contentType: 'application/json'
          examples: {
            sample: {
              summary: 'Create item request'
              value: {
                name: 'Notebook PC'
                description: 'Development laptop'
              }
            }
          }
        }
      ]
    }
    responses: [
      {
        statusCode: 201
        description: 'Returns the created item including its generated id.'
        representations: [
          {
            contentType: 'application/json'
            examples: {
              sample: {
                summary: 'Create item response'
                value: {
                  id: '11111111-1111-1111-1111-111111111111'
                  name: 'Notebook PC'
                  description: 'Development laptop'
                }
              }
            }
          }
        ]
      }
      {
        statusCode: 400
        description: 'Returned when the request body is not valid JSON or name is missing.'
      }
    ]
  }
  {
    name: 'get-item'
    displayName: 'Get item'
    method: 'GET'
    urlTemplate: '/items/{id}'
    description: 'Get a single item by id.'
    templateParameters: [
      {
        name: 'id'
        type: 'string'
        required: true
        description: 'The item id to retrieve.'
      }
    ]
    request: {
      description: 'No request body is required.'
      headers: []
      queryParameters: []
      representations: []
    }
    responses: [
      {
        statusCode: 200
        description: 'Returns the requested item.'
        representations: [
          {
            contentType: 'application/json'
            examples: {
              sample: {
                summary: 'Get item response'
                value: {
                  id: '11111111-1111-1111-1111-111111111111'
                  name: 'Notebook PC'
                  description: 'Development laptop'
                }
              }
            }
          }
        ]
      }
      {
        statusCode: 404
        description: 'Returned when the item does not exist.'
      }
    ]
  }
  {
    name: 'update-item'
    displayName: 'Update item'
    method: 'PUT'
    urlTemplate: '/items/{id}'
    description: 'Update an existing item by id. Provide one or both of name and description in the JSON body.'
    templateParameters: [
      {
        name: 'id'
        type: 'string'
        required: true
        description: 'The item id to update.'
      }
    ]
    request: {
      description: 'JSON body with fields to update.'
      headers: []
      queryParameters: []
      representations: [
        {
          contentType: 'application/json'
          examples: {
            sample: {
              summary: 'Update item request'
              value: {
                name: 'Notebook PC 14'
                description: 'Updated development laptop'
              }
            }
          }
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'Returns the updated item.'
        representations: [
          {
            contentType: 'application/json'
            examples: {
              sample: {
                summary: 'Update item response'
                value: {
                  id: '11111111-1111-1111-1111-111111111111'
                  name: 'Notebook PC 14'
                  description: 'Updated development laptop'
                }
              }
            }
          }
        ]
      }
      {
        statusCode: 400
        description: 'Returned when the request body is not valid JSON.'
      }
      {
        statusCode: 404
        description: 'Returned when the item does not exist.'
      }
    ]
  }
  {
    name: 'delete-item'
    displayName: 'Delete item'
    method: 'DELETE'
    urlTemplate: '/items/{id}'
    description: 'Delete a single item by id.'
    templateParameters: [
      {
        name: 'id'
        type: 'string'
        required: true
        description: 'The item id to delete.'
      }
    ]
    request: {
      description: 'No request body is required.'
      headers: []
      queryParameters: []
      representations: []
    }
    responses: [
      {
        statusCode: 200
        description: 'Returns the deleted item.'
        representations: [
          {
            contentType: 'application/json'
            examples: {
              sample: {
                summary: 'Delete item response'
                value: {
                  id: '11111111-1111-1111-1111-111111111111'
                  name: 'Notebook PC'
                  description: 'Development laptop'
                }
              }
            }
          }
        ]
      }
      {
        statusCode: 404
        description: 'Returned when the item does not exist.'
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
