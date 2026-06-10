@description('Location for all resources.')
param location string = resourceGroup().location

@description('Admin username for the VMs')
param adminUsername string = 'azureuser'

@description('Admin password for the VMs')
@secure()
param adminPassword string = newGuid()

// ============================================================
// このステップの主題
// ============================================================
// Step1〜4 では、NSG の許可/拒否や UDR の経路を「出し入れ」し、その結果を ping や ssh で
// 都度たしかめてきた（通った／通らない、を体で確認する）。
// 本ステップは、その「通った／通らない」を、後追いで説明できる形に**観測**する。
//
//   - IP Flow Verify : 「この通信は NSG で許可される？拒否される？ どのルールが効く？」を、
//                       実トラフィックを流さずに判定する（Step1/4 の NSG 検証を可視化）
//   - 接続トラブルシュート（connectivity test）: 実際に VM 間の疎通を試し、経路上のどこで
//                       到達/不達になったかを返す（ping の体験を、経路つきで説明できる形に）
//   - Next Hop        : 「この宛先へのパケットは次にどこへ向かう？」を UDR 込みで返す（Step3 の UDR 検証を可視化）
//   - NSG フローログ   : NSG を通過した許可/拒否トラフィックを Storage に**記録**する
//                       （都度の ping ではなく、後から見返せる通信ログ）
//
// 環境自体は Step1/4 を最小再現したもの（1 VNet・1 サブネット・NSG・private VM 2 台）。
// 主役はリソースではなく「観測のしかた」なので、構成は意図的に小さくしてある。

// 一意なストレージアカウント名（フローログの保存先）。名前はグローバル一意・小文字英数のみ。
var storageName = 'stflow${uniqueString(resourceGroup().id)}'

// ============================================================
// NSG（観測対象。Step1/4 と同じ「VNet 内からの SSH だけ許可」）
// ============================================================
// 既定では Internet からの inbound は最後の DenyAllInBound で拒否される。
// この「許可は明示ルール／拒否は既定ルール」という構図を、IP Flow Verify で可視化する。
resource nsgApp 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-app'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-From-Vnet'
        properties: {
          priority: 100
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
// VNet / サブネット（観測対象の最小環境）
// ============================================================
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'vnet-observe'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-app'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsgApp.id
          }
        }
      }
    ]
  }
}

// ============================================================
// VM 2 台（vm-a / vm-b）。どちらもパブリック IP なし。
// ============================================================
// vm-a を「観測する側（接続トラブルシュートの送信元）」、vm-b を「観測される側（宛先）」とする。
// 検証は az vm run-command と Network Watcher（プラットフォーム経由）で行うため、
// インターネットからの inbound は不要。
resource nicA 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-a'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource nicB 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-b'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
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
// Network Watcher Agent 拡張機能
// ============================================================
// 接続トラブルシュート（connectivity test）は、送信元 VM 内のエージェントが実際にパケットを
// 出して経路を測る。そのため対象 VM にこの拡張機能が必要（IP Flow Verify / Next Hop は
// NSG・ルートの評価なので拡張機能なしでも動くが、まとめて入れておく）。
resource agentA 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  parent: vmA
  name: 'NetworkWatcherAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.NetworkWatcher'
    type: 'NetworkWatcherAgentLinux'
    typeHandlerVersion: '1.4'
    autoUpgradeMinorVersion: true
  }
}

resource agentB 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  parent: vmB
  name: 'NetworkWatcherAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.NetworkWatcher'
    type: 'NetworkWatcherAgentLinux'
    typeHandlerVersion: '1.4'
    autoUpgradeMinorVersion: true
  }
}

// ============================================================
// フローログの保存先ストレージアカウント
// ============================================================
// NSG フローログ（許可/拒否トラフィックの記録）の出力先。フローログ自体の有効化は、
// Network Watcher を自動でハンドリングしてくれる `az network watcher flow-log create`
// （justfile の flow-log-on）で行う。Bicep からネットワークウォッチャー（別 RG の自動生成
// リソース）を参照すると煩雑になるため、保存先だけここで用意する。
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

output appNsgName string = nsgApp.name
output vmAPrivateIp string = nicA.properties.ipConfigurations[0].properties.privateIPAddress
output vmBPrivateIp string = nicB.properties.ipConfigurations[0].properties.privateIPAddress
output storageAccountName string = storage.name
