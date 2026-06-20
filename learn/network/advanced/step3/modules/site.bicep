// 1 サイト分のネットワーク基盤＋テスト VM。
// hub / onprem の 2 拠点で同じ構成を使い回すため、CIDR・名前・対向プレフィックスをパラメータ化している。
//
// サブネットは 2 つ:
//   - GatewaySubnet : VPN Gateway 専用（名前は固定で 'GatewaySubnet' でなければならない / NSG は付けない）
//   - subnet-workload : テスト VM を置く。NSG で「対向拠点からの 80/ICMP」だけ通す
//
// テスト VM には公開 IP を付けない。疎通確認は `az vm run-command`（Azure エージェント経由）で
// VM の "内側" から対向 VM の private IP に curl/ping することで行う（SSH の口を開けずに済む）。

@description('Location for all resources.')
param location string

@description('Name of the Virtual Network')
param vnetName string

@description('Address space for the VNet (e.g. 10.0.0.0/16)')
param vnetCidr string

@description('Address prefix for the workload subnet (test VM)')
param workloadCidr string

@description('Address prefix for the GatewaySubnet (VPN Gateway 専用)')
param gatewayCidr string

@description('Name of the test VM')
param vmName string

@description('Static private IP for the test VM')
param vmPrivateIp string

@description('対向拠点のアドレス空間。NSG で 80/ICMP の送信元として許可する')
param peerAddressSpace string

@description('Admin username for the VM')
param adminUsername string

@description('Admin password for the VM')
@secure()
param adminPassword string

// テスト VM の Nginx は「自分が誰か」を返す。トンネル越しに対向 VM へ curl したとき、
// どちらの拠点に届いたか（あるいは届かないか）を一目で判定できるようにする。
// 注: '''...''' の複数行文字列は変数補間しないため、vmName/vmPrivateIp を差し込む本スクリプトは
//     補間できる通常の文字列（\n で改行）で組み立てる。ヒアドキュメントの EOF は素のまま使う
//     （nginx 設定内に bash 変数を含めないので、シェル展開から守る必要がない）。
var vmCustomData = '#!/bin/bash\napt-get update\napt-get install -y nginx\ncat > /etc/nginx/sites-available/default <<EOF\nserver {\n    listen 80 default_server;\n    location / {\n        default_type text/plain;\n        return 200 "Reached ${vmName} (private-ip ${vmPrivateIp})\\n";\n    }\n}\nEOF\nsystemctl enable nginx\nsystemctl restart nginx\n'

// ワークロードサブネット用 NSG。
// - 対向拠点（peerAddressSpace）からの HTTP(80) と ICMP(ping) を明示的に許可する。
// - これが「トンネルが張れて経路が伝播していれば対向から届く」ことの受け皿。
// - GatewaySubnet には NSG を付けない（Azure 推奨。ゲートウェイの制御通信を壊さないため）。
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-${vmName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-From-Peer'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: peerAddressSpace
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-ICMP-From-Peer'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: peerAddressSpace
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
        vnetCidr
      ]
    }
    subnets: [
      {
        // VPN Gateway を置くサブネット。名前は必ず 'GatewaySubnet'
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: gatewayCidr
        }
      }
      {
        name: 'subnet-workload'
        properties: {
          addressPrefix: workloadCidr
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// テスト VM 用 NIC（公開 IP なし・private IP は固定）
resource nic 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-${vmName}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: vmPrivateIp
          subnet: {
            id: vnet.properties.subnets[1].id // subnet-workload
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(vmCustomData)
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
          id: nic.id
        }
      ]
    }
  }
}

// GatewaySubnet は subnets[0]
output gatewaySubnetId string = vnet.properties.subnets[0].id
output vmName string = vmName
output vmPrivateIp string = vmPrivateIp
