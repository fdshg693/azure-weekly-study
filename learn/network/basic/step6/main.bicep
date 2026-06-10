@description('Location for all resources.')
param location string = resourceGroup().location

@description('Admin username for the private VM')
param adminUsername string = 'azureuser'

@description('SSH public key (contents of azbastion_key.pub). Installed on the private VM so the same local private key authenticates the Bastion-relayed SSH session.')
param adminPublicKey string

// ============================================================
// このステップの主役：マネージドな踏み台「Azure Bastion」
// ============================================================
// Step4 では「踏み台 VM」を自前で立て、自分のグローバル IP にだけ SSH(22) を開き、
// ssh -J（ProxyJump）で private VM へ多段 SSH した。本ステップはそれを
// マネージドサービス（Azure Bastion）に肩代わりさせる。
//
// Step4 との最大の違い（＝学びどころ）:
//   - 踏み台 VM が無い：OS のパッチ当て・sshd 設定・公開鍵管理を自分で持たない。
//   - private VM はもちろん、踏み台にも「インターネットへ開いた 22 番」が無い。
//     利用者は Azure の認証済みセッション（CLI / ポータル）経由で Bastion に到達する。
//     ＝「自分の IP を NSG に登録する」必要が無い（Step4 の myIp パラメータが消えている）。
//   - 接続経路は Azure Bastion → private VM の "プライベート IP:22"。
//     よって private VM 側の NSG は「AzureBastionSubnet から来る SSH」を許可する。

// ============================================================
// NSG（private サブネットのアクセス制御）
// ============================================================
// Azure Bastion は AzureBastionSubnet 内のホストとして、対象 VM の
// プライベート IP の 22 番へ接続してくる。だから許可する送信元は
// 「あなたのグローバル IP」ではなく「AzureBastionSubnet のレンジ」になる。
// （Step4 では送信元が踏み台サブネットだった。考え方は同じで、踏み台の正体が変わっただけ）
resource nsgPrivate 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-private'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-From-Bastion'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          // Azure Bastion が居る専用サブネット。ここから来る SSH だけを許可する（最小権限）。
          sourceAddressPrefix: '10.0.0.0/26'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ============================================================
// VNet（Bastion 専用サブネット / 非公開ゾーン）
// ============================================================
// AzureBastionSubnet は Azure Bastion 専用の "予約名" サブネット。
//   - 名前は必ず `AzureBastionSubnet`（これ以外だと Bastion を配置できない）。
//   - 最小サイズは /26（Standard SKU では /26 以上が必要）。
//   - ここには VM を置かない。Bastion 専用に空けておく。
// 通常このサブネットに NSG は付けなくてよい（Azure が必要な通信を管理する）。
// 付ける場合は Microsoft が定める必須ルール一式が要るため、学習では付けない。
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-azbastion'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        // 予約名。Azure Bastion はこの名前のサブネットを探して配置される。
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.0.0/26'
        }
      }
      {
        // 保護対象（パブリック IP なし）を置く非公開ゾーン。
        name: 'subnet-private'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsgPrivate.id
          }
        }
      }
    ]
  }
}

// ============================================================
// Azure Bastion（マネージドな踏み台）＋ その公開 IP
// ============================================================
// Bastion 自身は AzureBastionSubnet に入り、Standard SKU の静的パブリック IP を 1 つ持つ。
// この公開 IP は「Azure の Bastion サービスのフロント」であって、踏み台 VM の 22 番が
// 生で開いているわけではない（利用者は az / ポータルの認証済みセッションで到達する）。

resource publicIpBastion 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-azbastion'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: 'azbastion'
  location: location
  // Standard SKU。Basic では使えない「ネイティブクライアント対応（トンネリング）」を
  // 有効にしておくと、ブラウザのポータルだけでなく az CLI / ローカル ssh から接続できる。
  sku: {
    name: 'Standard'
  }
  properties: {
    // az network bastion ssh / tunnel（ローカルの ssh クライアントから接続）に必要。
    enableTunneling: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            // 必ず AzureBastionSubnet を指す。
            id: vnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: publicIpBastion.id
          }
        }
      }
    ]
  }
}

// ============================================================
// private VM（パブリック IP なし・本ステップの保護対象）
// ============================================================
// Step4 の private VM と同じ立ち位置。パブリック IP を付けないので、外から直接は入れない。
// 唯一の入口は Azure Bastion（AzureBastionSubnet 経由の SSH）。
// 踏み台 VM が無いので、cloud-init での AllowTcpForwarding 設定（Step4）はもう要らない
// ＝中継の責務は Azure Bastion 側が持つ。VM は普通に SSH を受けるだけ。

resource nicPrivate 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-private'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet.properties.subnets[1].id
          }
        }
      }
    ]
  }
}

resource vmPrivate 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-private'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm-private'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey
            }
          ]
        }
      }
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
          id: nicPrivate.id
        }
      ]
    }
  }
}

output bastionName string = bastion.name
output bastionPublicIp string = publicIpBastion.properties.ipAddress
// az network bastion ssh / tunnel は接続先を「VM のリソース ID」で指定する。
output privateVmId string = vmPrivate.id
output privateVmName string = vmPrivate.name
output privatePrivateIp string = nicPrivate.properties.ipConfigurations[0].properties.privateIPAddress
