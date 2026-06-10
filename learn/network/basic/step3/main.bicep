@description('Location for all resources.')
param location string = resourceGroup().location

@description('Admin username for the VMs')
param adminUsername string = 'azureuser'

@description('Admin password for the VMs')
@secure()
param adminPassword string = newGuid()

// NVA（ハブの中継 VM）の固定プライベート IP。
// ルートテーブルの next hop としてこの値を参照するため、静的に固定しておく。
// （サブネットの先頭 .0〜.3 は Azure が予約しているため、最初に使えるのは .4）
var nvaPrivateIp = '10.0.0.4'

// NVA を起動時に「ルーター化」するための cloud-init。
// Linux はデフォルトでは受け取ったパケットを転送しない（自分宛て以外は破棄する）。
// net.ipv4.ip_forward = 1 にすることで、自分宛てでないパケットを転送（ルーティング）するようになる。
var nvaCloudInit = '''
#cloud-config
write_files:
  - path: /etc/sysctl.d/99-ip-forward.conf
    content: |
      net.ipv4.ip_forward = 1
runcmd:
  - sysctl --system
'''

// ============================================================
// NSG（各サブネットのアクセス制御）
// ============================================================

// --- Hub（NVA）用 NSG ---
// ハブは spoke1・spoke2 の両方とピアリングしているため、ハブの「VirtualNetwork」タグには
// 10.0/16・10.1/16・10.2/16 がすべて含まれる。よって spoke1↔spoke2 の転送トラフィックは
// 既定ルール AllowVnetInBound/OutBound で通る。ここでは管理用に SSH/ICMP を明示許可するだけ。
resource nsgNva 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-nva'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-ICMP-From-Vnet'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SSH-From-Vnet'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// --- Spoke1 用 NSG（疎通テストの起点・パブリック IP あり）---
// spoke1 は hub としかピアリングしていないため、spoke1 の VirtualNetwork タグには
// spoke2（10.2/16）が含まれない。そのため spoke2 宛て/spoke2 からの通信は
// 既定ルールではカバーされず、ICMP を明示的に許可する必要がある。
resource nsgSpoke1 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-spoke1'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-Inbound'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-ICMP-Inbound'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Icmp'
          sourcePortRange: '*'
          // spoke2 からの ping 応答（src 10.2.x）や、NVA からの経路上の ICMP も受け取れるよう
          // 入口である spoke1 は送信元を限定しない。
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-ICMP-To-Spoke2-Outbound'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Outbound'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          // spoke2（10.2/16）は spoke1 の VirtualNetwork タグに含まれないため、
          // 既定の AllowVnetOutBound では通らない。明示的に送信を許可する。
          destinationAddressPrefix: '10.2.0.0/16'
        }
      }
    ]
  }
}

// --- Spoke2 用 NSG（隔離された宛先・パブリック IP なし）---
// NVA はパケットを転送するだけで送信元 IP を書き換えない（NAT しない）。
// そのため spoke2 に届く ping の送信元は「元の spoke1 の IP（10.1.x）」のまま。
// spoke2 から見ると 10.1/16 は VirtualNetwork タグ外なので、明示的な許可が必須。
resource nsgSpoke2 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-spoke2'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-ICMP-From-Spoke1'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          // 受け取る ICMP は spoke1（subnet-spoke1）からのものだけに限定（最小権限）。
          sourceAddressPrefix: '10.1.0.0/24'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-ICMP-To-Spoke1-Outbound'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Outbound'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          // ping 応答を spoke1（10.1/16）へ返す。spoke1 は VirtualNetwork タグ外なので明示許可。
          destinationAddressPrefix: '10.1.0.0/16'
        }
      }
    ]
  }
}

// ============================================================
// ルートテーブル（UDR / ユーザー定義ルート）
// ============================================================
// spoke1・spoke2 は直接ピアリングしていない（ピアリングは推移しない）。
// そのため、相手の spoke 宛てのトラフィックを「ハブの NVA 経由」に向けるルートを定義する。
// next hop を VirtualAppliance（= NVA のプライベート IP）にするのがポイント。

resource rtSpoke1 'Microsoft.Network/routeTables@2023-04-01' = {
  name: 'rt-spoke1'
  location: location
  properties: {
    routes: [
      {
        name: 'to-spoke2'
        properties: {
          addressPrefix: '10.2.0.0/16'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: nvaPrivateIp
        }
      }
    ]
  }
}

resource rtSpoke2 'Microsoft.Network/routeTables@2023-04-01' = {
  name: 'rt-spoke2'
  location: location
  properties: {
    routes: [
      {
        name: 'to-spoke1'
        properties: {
          addressPrefix: '10.1.0.0/16'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: nvaPrivateIp
        }
      }
    ]
  }
}

// ============================================================
// VNet（ハブ + 2つのスポーク）
// ============================================================

resource vnetHub 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'vnet-hub'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-nva'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: nsgNva.id
          }
        }
      }
    ]
  }
}

resource vnetSpoke1 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'vnet-spoke1'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-spoke1'
        properties: {
          addressPrefix: '10.1.0.0/24'
          networkSecurityGroup: {
            id: nsgSpoke1.id
          }
          routeTable: {
            id: rtSpoke1.id
          }
        }
      }
    ]
  }
}

resource vnetSpoke2 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'vnet-spoke2'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.2.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-spoke2'
        properties: {
          addressPrefix: '10.2.0.0/24'
          networkSecurityGroup: {
            id: nsgSpoke2.id
          }
          routeTable: {
            id: rtSpoke2.id
          }
        }
      }
    ]
  }
}

// ============================================================
// NVA（ハブの中継 VM）
// ============================================================

resource nicNva 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-nva'
  location: location
  // enableIPForwarding: 自分宛てでないパケットの送受信を Azure ネットワーク層で許可する。
  // OS 側の net.ipv4.ip_forward と「両方」有効にして初めて NVA はルーターとして機能する。
  properties: {
    enableIPForwarding: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          // ルートテーブルの next hop として参照するため、静的に固定する。
          privateIPAllocationMethod: 'Static'
          privateIPAddress: nvaPrivateIp
          subnet: {
            id: vnetHub.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource vmNva 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-nva'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm-nva'
      adminUsername: adminUsername
      adminPassword: adminPassword
      // cloud-init で IP フォワーディングを有効化する
      customData: base64(nvaCloudInit)
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
          id: nicNva.id
        }
      ]
    }
  }
}

// ============================================================
// Spoke1 VM（疎通テストの起点・パブリック IP あり）
// ============================================================

resource publicIpSpoke1 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: 'pip-spoke1'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nicSpoke1 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-spoke1'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIpSpoke1.id
          }
          subnet: {
            id: vnetSpoke1.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource vmSpoke1 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-spoke1'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm-spoke1'
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
          id: nicSpoke1.id
        }
      ]
    }
  }
}

// ============================================================
// Spoke2 VM（隔離された宛先・パブリック IP なし）
// ============================================================
// パブリック IP を付けないことで、spoke1 からの疎通成功が確実に
// 「UDR → NVA 経由のプライベート通信」であることを担保する（Step2 と同じ考え方）。

resource nicSpoke2 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-spoke2'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnetSpoke2.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource vmSpoke2 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-spoke2'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm-spoke2'
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
          id: nicSpoke2.id
        }
      ]
    }
  }
}

// ============================================================
// VNet ピアリング（hub ↔ spoke1、hub ↔ spoke2）
// ============================================================
// spoke1 ↔ spoke2 は「あえて」ピアリングしない。これにより、spoke 間通信が
// 直接ピアリングではなく UDR + NVA 経由で成立していることを保証する。
//
// allowForwardedTraffic（転送トラフィックの許可）について:
//   NVA が転送するパケットは「送信元がハブの外（spoke の IP）」のため、
//   ハブ → spoke 方向のピアリングでは「転送トラフィック」として扱われる。
//   よって hub→spoke1 / hub→spoke2 のピアリングで allowForwardedTraffic = true が必須。

resource peeringHubToSpoke1 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  parent: vnetHub
  name: 'peering-hub-to-spoke1'
  properties: {
    allowVirtualNetworkAccess: true
    // NVA が spoke2→spoke1 の応答を spoke1 へ転送するため true が必要。
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnetSpoke1.id
    }
  }
}

resource peeringSpoke1ToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  parent: vnetSpoke1
  name: 'peering-spoke1-to-hub'
  properties: {
    allowVirtualNetworkAccess: true
    // spoke1 → ハブ方向に転送トラフィックは流れないため false（最小権限）。
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnetHub.id
    }
  }
}

resource peeringHubToSpoke2 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  parent: vnetHub
  name: 'peering-hub-to-spoke2'
  properties: {
    allowVirtualNetworkAccess: true
    // NVA が spoke1→spoke2 の通信を spoke2 へ転送するため true が必要。
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnetSpoke2.id
    }
  }
}

resource peeringSpoke2ToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  parent: vnetSpoke2
  name: 'peering-spoke2-to-hub'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnetHub.id
    }
  }
}

output nvaPrivateIp string = nvaPrivateIp
output vmSpoke1PublicIp string = publicIpSpoke1.properties.ipAddress
output vmSpoke1PrivateIp string = nicSpoke1.properties.ipConfigurations[0].properties.privateIPAddress
output vmSpoke2PrivateIp string = nicSpoke2.properties.ipConfigurations[0].properties.privateIPAddress
