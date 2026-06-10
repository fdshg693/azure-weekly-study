@description('Location for all resources.')
param location string = resourceGroup().location

@description('Name of the Virtual Network')
param vnetName string = 'vnet-appgw'

@description('Address prefix for the Virtual Network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for the Application Gateway subnet (dedicated)')
param appgwSubnetPrefix string = '10.0.1.0/24'

@description('Address prefix for the backend subnet')
param backendSubnetPrefix string = '10.0.2.0/24'

@description('Admin username for the VMs')
param adminUsername string = 'azureuser'

@description('Admin password for the VMs')
@secure()
param adminPassword string = newGuid()

@description('Static private IP for the WEB backend VM')
param webPrivateIp string = '10.0.2.4'

@description('Static private IP for the API backend VM')
param apiPrivateIp string = '10.0.2.5'

var appgwName = 'appgw'

// 1-a. NSG for Application Gateway subnet
// Application Gateway v2 では GatewayManager からの管理トラフィック(65200-65535)を許可する必要がある
resource nsgAppgw 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-appgw'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-Inbound'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
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

// 1-b. NSG for backend subnet
resource nsgBackend 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-backend'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-Inbound'
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

// 2. Virtual Network with two subnets (appgw 専用 / backend)
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

// 3. Public IP for Application Gateway (Standard SKU 必須)
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

// 4. Backend VMs (WEB / API)
// どのパスへアクセスされても自分の役割を返すように Nginx を設定する
var webCustomData = '''
#!/bin/bash
apt-get update
apt-get install -y nginx
cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    location / {
        default_type text/plain;
        return 200 "Response from WEB backend (vm-web)\n";
    }
}
EOF
systemctl enable nginx
systemctl restart nginx
'''

var apiCustomData = '''
#!/bin/bash
apt-get update
apt-get install -y nginx
cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    location / {
        default_type text/plain;
        return 200 "Response from API backend (vm-api)\n";
    }
}
EOF
systemctl enable nginx
systemctl restart nginx
'''

resource nicWeb 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-vm-web'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: webPrivateIp
          subnet: {
            id: vnet.properties.subnets[1].id
          }
        }
      }
    ]
  }
}

resource nicApi 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-vm-api'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: apiPrivateIp
          subnet: {
            id: vnet.properties.subnets[1].id
          }
        }
      }
    ]
  }
}

resource vmWeb 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-web'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm-web'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(webCustomData)
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicWeb.id
        }
      ]
    }
  }
}

resource vmApi 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-api'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm-api'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(apiCustomData)
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicApi.id
        }
      ]
    }
  }
}

// 5. Application Gateway (Standard_v2) — L7 パスベースルーティング
// 各構成要素を resourceId で相互参照するため、id を組み立てるヘルパ変数を用意する
var appgwId = resourceId('Microsoft.Network/applicationGateways', appgwName)

resource appgw 'Microsoft.Network/applicationGateways@2023-04-01' = {
  name: appgwName
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 1
    }
    gatewayIPConfigurations: [
      {
        name: 'appgw-ip-config'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appgw-frontend-ip'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port-80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'web-pool'
        properties: {
          backendAddresses: [
            {
              ipAddress: webPrivateIp
            }
          ]
        }
      }
      {
        name: 'api-pool'
        properties: {
          backendAddresses: [
            {
              ipAddress: apiPrivateIp
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'http-settings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 20
        }
      }
    ]
    httpListeners: [
      {
        name: 'http-listener'
        properties: {
          frontendIPConfiguration: {
            id: '${appgwId}/frontendIPConfigurations/appgw-frontend-ip'
          }
          frontendPort: {
            id: '${appgwId}/frontendPorts/port-80'
          }
          protocol: 'Http'
        }
      }
    ]
    // URL パスマップ: /api/* は api-pool、それ以外は web-pool（既定）
    urlPathMaps: [
      {
        name: 'path-map'
        properties: {
          defaultBackendAddressPool: {
            id: '${appgwId}/backendAddressPools/web-pool'
          }
          defaultBackendHttpSettings: {
            id: '${appgwId}/backendHttpSettingsCollection/http-settings'
          }
          pathRules: [
            {
              name: 'api-rule'
              properties: {
                paths: [
                  '/api/*'
                ]
                backendAddressPool: {
                  id: '${appgwId}/backendAddressPools/api-pool'
                }
                backendHttpSettings: {
                  id: '${appgwId}/backendHttpSettingsCollection/http-settings'
                }
              }
            }
          ]
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'path-based-rule'
        properties: {
          ruleType: 'PathBasedRouting'
          priority: 100
          httpListener: {
            id: '${appgwId}/httpListeners/http-listener'
          }
          urlPathMap: {
            id: '${appgwId}/urlPathMaps/path-map'
          }
        }
      }
    ]
  }
  dependsOn: [
    vmWeb
    vmApi
  ]
}

output appGatewayPublicIp string = publicIp.properties.ipAddress
