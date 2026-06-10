// ネットワーク基盤: VNet・1 サブネット（origin）・NSG・Public IP（DNS ラベル付き）
// ねらいは「オリジン（バックエンド）を直接インターネットに晒さず、エッジ(Front Door)経由でしか
// 到達できないようにする」こと。NSG で送信元を service tag `AzureFrontDoor.Backend` だけに絞る。

@description('Location for all resources.')
param location string

@description('Name of the Virtual Network')
param vnetName string = 'vnet-edge'

@description('Address prefix for the Virtual Network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for the origin subnet')
param originSubnetPrefix string = '10.0.1.0/24'

@description('DNS label for the origin public IP (must be globally unique within the region)')
param dnsLabel string = 'origin-${uniqueString(resourceGroup().id)}'

// オリジンサブネットの NSG
// - 既定では HTTP(80) を service tag `AzureFrontDoor.Backend`（= Front Door のバックエンド向き IP 群）からだけ許可する。
// - インターネットからの直アクセスは「明示許可が無い → 既定 Deny」で塞がる（= エッジ経由を強制）。
// - 検証用に `just unlock-origin` が Allow-Direct-Internet ルールを足し、`just lock-origin` が外す。
resource nsgOrigin 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-origin'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-From-FrontDoor'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'subnet-origin'
        properties: {
          addressPrefix: originSubnetPrefix
          networkSecurityGroup: {
            id: nsgOrigin.id
          }
        }
      }
    ]
  }
}

// オリジン VM 用 Public IP。Front Door の origin は FQDN で指定するため DNS ラベルを付ける。
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: 'pip-origin'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: dnsLabel
    }
  }
}

output originSubnetId string = vnet.properties.subnets[0].id
output publicIpId string = publicIp.id
output publicIpAddress string = publicIp.properties.ipAddress
output originFqdn string = publicIp.properties.dnsSettings.fqdn
