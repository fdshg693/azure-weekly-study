// ネットワーク基盤: VNet・2 サブネット（appgw 専用 / backend）・NSG・Public IP
// Step10 と同じ骨格だが、入口を HTTP:80 ではなく HTTPS:443 にしている点が違い（TLS 終端のため）。

@description('Location for all resources.')
param location string

@description('Name of the Virtual Network')
param vnetName string = 'vnet-waf'

@description('Address prefix for the Virtual Network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for the Application Gateway subnet (dedicated)')
param appgwSubnetPrefix string = '10.0.1.0/24'

@description('Address prefix for the backend subnet')
param backendSubnetPrefix string = '10.0.2.0/24'

// Application Gateway 専用サブネットの NSG
// - Internet からの HTTPS(443) を許可（入口）
// - WAF_v2 の管理トラフィック GatewayManager(65200-65535) を許可（必須）
resource nsgAppgw 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-appgw'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS-Inbound'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-GatewayManager-Inbound'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// バックエンドサブネットの NSG: VNet 内（= Application Gateway）からの HTTP(80) のみ許可
resource nsgBackend 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-backend'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-From-Vnet'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'VirtualNetwork'
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
        name: 'subnet-appgw'
        properties: {
          addressPrefix: appgwSubnetPrefix
          networkSecurityGroup: {
            id: nsgAppgw.id
          }
        }
      }
      {
        name: 'subnet-backend'
        properties: {
          addressPrefix: backendSubnetPrefix
          networkSecurityGroup: {
            id: nsgBackend.id
          }
        }
      }
    ]
  }
}

// Application Gateway 用 Public IP（WAF_v2 は Standard SKU / Static 必須）
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: 'pip-appgw'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

output appgwSubnetId string = vnet.properties.subnets[0].id
output backendSubnetId string = vnet.properties.subnets[1].id
output publicIpId string = publicIp.id
output publicIpAddress string = publicIp.properties.ipAddress
