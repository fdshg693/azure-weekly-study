// Linux App Service プラン。BFF(Node) と 読み取り API(Python) の 2 つの Web App が相乗りする。
// 学習向けに最小の Basic B1。

@description('リージョン')
param location string

@description('プラン名')
param planName string

param tags object = {}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  tags: tags
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  kind: 'linux'
  properties: {
    reserved: true // Linux プランは reserved: true が必須
  }
}

output planId string = plan.id
