@description('Location for all resources.')
param location string = resourceGroup().location

@description('Admin username for the VMs')
param adminUsername string = 'azureuser'

@description('Admin password for the VMs (auto-generated; we connect via Run Command, not SSH, so it is never used interactively)')
@secure()
param adminPassword string = newGuid()

// ============================================================
// このステップの主役：プライベートな「名前解決」= Private DNS Zone
// ============================================================
// Step1〜6 では宛先をすべて「プライベート IP の直打ち」（例: ping 10.0.1.5）で指定してきた。
// IP は動的だったり分かりにくかったりするので、現実の運用では「名前」で到達したい。
// 本ステップは、VNet 内だけで通用する独自のゾーン（corp.internal）を用意し、
//   - VM が起動時に自分の名前を自動登録する（自動登録 / auto-registration）
//   - 人が分かりやすい別名を手動で登録する（手動レコード）
// の 2 通りで「名前 → プライベート IP」の対応を持たせ、`vm-b.corp.internal` のような
// 名前で ping できることを確認する。
//
// ポイント（＝学びどころ）:
//   - 名前解決は VNet と Private DNS Zone を「リンク」して初めて効く。
//     リンクを外すと「名前は引けないが IP では届く」状態になり、DNS が解決を担っている
//     ことが切り分けられる（他ステップの NSG/UDR/NAT GW の出し入れと同じ検証手法）。
//   - 自動登録は「リンクの registrationEnabled = true」で有効になる（ゾーンにつき 1 リンクのみ）。

// ============================================================
// NSG（VNet 内からの ICMP / SSH を許可）
// ============================================================
// 検証は Azure VM Run Command で vm-a 上から vm-b へ ping する（Step2 と同じやり方）。
// vm-b が ICMP を受け取れるよう、VNet 内からの ICMP を許可する。SSH も内部用に開けておく。
resource nsgMain 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-main'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-ICMP-From-VNet'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          // 同じ VNet 内からの ICMP だけ許可（名前で引いても IP で引いても、最終的に届く先は同じ VM）。
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SSH-From-VNet'
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

// ============================================================
// VNet（名前解決を効かせたい単一の VNet）
// ============================================================
// VM のプライベート IP を「静的」にして、名前 → IP の対応を分かりやすく固定する。
//   - vm-a = 10.0.1.4
//   - vm-b = 10.0.1.5
// （Azure はサブネットの先頭 .0〜.3 を予約するので .4 から使う）
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-privatedns'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-main'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsgMain.id
          }
        }
      }
    ]
  }
}

// ============================================================
// 2 台の VM（パブリック IP なし。名前で互いに到達できるかを確認する）
// ============================================================
// computerName（= OS のホスト名）が、自動登録される A レコード名になる。
//   computerName 'vm-a' → ゾーン corp.internal に 'vm-a' という A レコードが自動で増える
//   → FQDN は vm-a.corp.internal。
resource nicA 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-vm-a'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.0.1.4'
          subnet: {
            id: vnet.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource nicB 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-vm-b'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.0.1.5'
          subnet: {
            id: vnet.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource vmA 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-a'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      // このホスト名が corp.internal に自動登録される（→ vm-a.corp.internal）。
      computerName: 'vm-a'
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
          id: nicA.id
        }
      ]
    }
  }
}

resource vmB 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-b'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm-b'
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
          id: nicB.id
        }
      ]
    }
  }
}

// ============================================================
// Private DNS Zone（VNet 内だけで通用する独自ゾーン）
// ============================================================
// Private DNS Zone は「グローバル」リソース（location: 'global'）。インターネットの
// パブリック DNS には一切公開されず、リンクした VNet の中からだけ引ける名前空間になる。
// 名前はドメイン名の形をしていれば自由（ここでは学習用に corp.internal）。
resource dnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'corp.internal'
  location: 'global'
}

// VNet とゾーンの「リンク」。これが無いと、VNet 内の VM はこのゾーンを引けない。
//   - registrationEnabled: true … この VNet の VM が起動時に自分のホスト名を自動登録する。
//     （自動登録を持てるリンクはゾーンにつき 1 つだけ）
// このリンクを外す/付け直すことで「名前解決を効かせているのは Private DNS Zone」だと
// 切り分けられる（justfile の unlink / link）。
resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: dnsZone
  name: 'link-to-vnet'
  location: 'global'
  properties: {
    registrationEnabled: true
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// ============================================================
// 手動レコード（人が決めた「別名」→ IP）
// ============================================================
// 自動登録される vm-a / vm-b とは別に、用途を表す分かりやすい名前を手で付ける例。
// app.corp.internal を vm-b(10.0.1.5) に向ける。VM のホスト名と違い、こちらは
// 「どの IP を指すか」を人が明示的に決める（リンクの自動登録とは独立に存在する）。
resource recordApp 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: dnsZone
  name: 'app'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: '10.0.1.5'
      }
    ]
  }
}

output dnsZoneName string = dnsZone.name
output vmAPrivateIp string = nicA.properties.ipConfigurations[0].properties.privateIPAddress
output vmBPrivateIp string = nicB.properties.ipConfigurations[0].properties.privateIPAddress
