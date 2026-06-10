@description('Location for all resources.')
param location string = resourceGroup().location

@description('Admin username for the VMs')
param adminUsername string = 'azureuser'

@description('Admin password for the VMs')
@secure()
param adminPassword string = newGuid()

// VNet 1 Resources
resource nsg1 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-vnet1'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-ICMP-Inbound'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SSH-Inbound'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource vnet1 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'vnet-1'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-1'
        properties: {
          addressPrefix: '10.1.0.0/24'
          networkSecurityGroup: {
            id: nsg1.id
          }
        }
      }
    ]
  }
}

resource publicIp1 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: 'pip-vm1'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic1 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-vm1'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp1.id
          }
          subnet: {
            id: vnet1.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource vm1 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-1'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm-1'
      adminUsername: adminUsername
      adminPassword: adminPassword
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
          id: nic1.id
        }
      ]
    }
  }
}

// VNet 2 Resources
resource nsg2 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-vnet2'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-ICMP-From-Subnet1'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          // vm2 が受け取る ICMP は subnet-1 (vm1) からのものだけ。
          // 送信元を subnet-1 のアドレス空間に限定し、最小権限とする。
          // これにより、疎通成功が確実に VNet ピアリング経由であることを NSG レベルでも担保する。
          sourceAddressPrefix: '10.1.0.0/24'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SSH-From-Subnet1'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          // SSH も同様に subnet-1 からのみ許可（vm2 にパブリック IP は無いが、明示的に限定する）。
          sourceAddressPrefix: '10.1.0.0/24'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource vnet2 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'vnet-2'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.2.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-2'
        properties: {
          addressPrefix: '10.2.0.0/24'
          networkSecurityGroup: {
            id: nsg2.id
          }
        }
      }
    ]
  }
}

resource nic2 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-vm2'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet2.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource vm2 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-2'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm-2'
      adminUsername: adminUsername
      adminPassword: adminPassword
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
          id: nic2.id
        }
      ]
    }
  }
}

// VNet Peering
resource peering1to2 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  parent: vnet1
  name: 'peering-vnet1-to-vnet2'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnet2.id
    }
  }
}

resource peering2to1 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  parent: vnet2
  name: 'peering-vnet2-to-vnet1'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnet1.id
    }
  }
}

output vm1PublicIp string = publicIp1.properties.ipAddress
output vm1PrivateIp string = nic1.properties.ipConfigurations[0].properties.privateIPAddress
output vm2PrivateIp string = nic2.properties.ipConfigurations[0].properties.privateIPAddress
