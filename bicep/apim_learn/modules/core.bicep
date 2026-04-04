@description('Azure リソースをデプロイするリージョン')
param location string

@description('リソース名のプレフィックス')
param prefix string

@description('一意性を確保するためのサフィックス')
param suffix string

@description('App Service Plan の SKU')
param servicePlanSku string

@description('リソースに適用するタグ')
param tags object

var storageAccountName = toLower(take('st${prefix}${suffix}aaa', 24))
var servicePlanName = 'plan-${prefix}-${suffix}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
  tags: tags
}

resource servicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: servicePlanName
  location: location
  kind: 'linux'
  sku: {
    name: servicePlanSku
  }
  properties: {
    reserved: true
  }
  tags: tags
}

output storageAccountName string = storageAccount.name
output servicePlanId string = servicePlan.id
