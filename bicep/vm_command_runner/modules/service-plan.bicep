@description('Azure リソースをデプロイするリージョン')
param location string

@description('App Service Plan 名')
param servicePlanName string

@description('SKU 名 (EP1/EP2/EP3)')
param servicePlanSku string

@description('リソースに適用するタグ')
param tags object

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: servicePlanName
  location: location
  kind: 'elastic'
  sku: {
    name: servicePlanSku
    tier: 'ElasticPremium'
  }
  properties: {
    reserved: true // Linux
    maximumElasticWorkerCount: 1
  }
  tags: tags
}

output servicePlanId string = plan.id
