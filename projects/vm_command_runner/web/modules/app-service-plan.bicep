@description('リージョン')
param location string

@description('App Service Plan 名')
param planName string

@description('SKU')
param sku string

@description('タグ')
param tags object

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  sku: {
    name: sku
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
  tags: tags
}

output id string = plan.id
output name string = plan.name
