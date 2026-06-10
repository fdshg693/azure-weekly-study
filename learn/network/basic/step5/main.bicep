@description('Location for all resources.')
param location string = resourceGroup().location

@description('Admin username for the VMs')
param adminUsername string = 'azureuser'

@description('SSH public key (contents of natgw_key.pub). Installed on BOTH VMs so the same local private key authenticates each hop.')
param adminPublicKey string

@description('Your global (public) IP address. Only this IP is allowed to SSH into the bastion host.')
param myIp string

// 踏み台（bastion）の固定プライベート IP。Step4 と同じく、private VM 側の NSG が
// 「踏み台サブネットからの SSH のみ許可」を判定するのはサブネット範囲だが、固定だと追いやすい。
// （サブネットの先頭 .0〜.3 は Azure が予約しているため、最初に使えるのは .4）
var bastionPrivateIp = '10.0.0.4'

// 踏み台 VM に渡す cloud-init（Step4 と同一の役割）。
// 本ステップの主役は「private VM の外向き通信」だが、その private VM はパブリック IP を
// 持たないため、確認のために踏み台越し（ssh -J）で中へ入る。ProxyJump の中継には
// 踏み台の sshd で AllowTcpForwarding が有効である必要があるので明示しておく。
var bastionCloudInit = '''#cloud-config
write_files:
  - path: /etc/ssh/sshd_config.d/10-allow-tcp-forwarding.conf
    permissions: '0644'
    content: |
      # ProxyJump (ssh -J) の中継に必要。踏み台が private VM への TCP 接続を転送できるようにする。
      AllowTcpForwarding yes
runcmd:
  - systemctl restart ssh
'''

// ============================================================
// NSG（各サブネットのアクセス制御）
// ============================================================
// 本ステップの肝：「inbound を閉じる」と「outbound を許す」は別物。
// private VM の NSG は inbound を踏み台サブネットだけに絞る（＝受信は閉じたまま）が、
// outbound は塞いでいない。実際に外へ出られるか否かは、サブネットに NAT Gateway が
// 付いているか（＝出口があるか）で決まる。NSG とは別レイヤの話であることを体感する。

// --- 踏み台サブネット用 NSG（唯一インターネットに開く「入口」）---
// 踏み台は確認用の入口。SSH の送信元を「自分のグローバル IP だけ」に絞る（Step4 と同じ）。
resource nsgBastion 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-bastion'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-From-MyIp'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '${myIp}/32'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// --- private サブネット用 NSG（保護対象・パブリック IP なし）---
// inbound は踏み台サブネット(10.0.0.0/24)からの SSH だけ許可（受信は閉じている）。
// outbound ルールは置かない＝NSG 上は外向き通信を妨げていない。
// それでも「出口（NAT Gateway）」が無ければ外へは出られない、という点が本ステップの主題。
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
          sourceAddressPrefix: '10.0.0.0/24'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ============================================================
// NAT Gateway（private VM の「外向きの出口」＝ SNAT）
// ============================================================
// パブリック IP を持たないホストでも、OS 更新やパッケージ取得などで「外へ出る」通信は要る。
// NAT Gateway は、サブネット内の全ホストの outbound を 1 つのパブリック IP（出口）に
// 集約（SNAT）する。受信用の入口は一切開かない＝「送信だけの一方向の出口」である点が要点。
// （Load Balancer のように inbound の宛先になるわけではない）

// NAT Gateway が名乗る出口のパブリック IP。private VM が外へ出るとき、
// 外部のサーバから見た送信元 IP はこの IP になる（SNAT）。Standard SKU が必須。
resource natPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-natgw'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource natGateway 'Microsoft.Network/natGateways@2023-11-01' = {
  name: 'natgw'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      {
        id: natPublicIp.id
      }
    ]
  }
}

// ============================================================
// VNet（公開ゾーン=踏み台 / 非公開ゾーン=private VM）
// ============================================================
// subnet-private には NAT Gateway を関連付ける。さらに defaultOutboundAccess を false にして、
// 「NAT Gateway を外したら本当に外へ出られなくなる」状態を作る（後述）。
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-natgw'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-bastion'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: nsgBastion.id
          }
        }
      }
      {
        name: 'subnet-private'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsgPrivate.id
          }
          // このサブネットの outbound の出口は NAT Gateway に集約する。
          natGateway: {
            id: natGateway.id
          }
          // Azure の「既定の送信アクセス（default outbound access）」を無効化する。
          // これを false にしないと、NAT Gateway を外しても Azure 暗黙の共有 SNAT で
          // 外に出られてしまい、「NAT Gateway が egress を成立させている」対比がぼやける。
          // false にすることで「出口＝NAT Gateway だけ」になり、外すと確実に egress が止まる。
          // （Azure は既定の送信アクセスを将来廃止する方針で、明示する方が今後の標準でもある）
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

// ============================================================
// 踏み台 VM（パブリック IP あり・確認用の入口）
// ============================================================

resource publicIpBastion 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-bastion'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nicBastion 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-bastion'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: bastionPrivateIp
          publicIPAddress: {
            id: publicIpBastion.id
          }
          subnet: {
            id: vnet.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource vmBastion 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-bastion'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm-bastion'
      adminUsername: adminUsername
      customData: base64(bastionCloudInit)
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
          id: nicBastion.id
        }
      ]
    }
  }
}

// ============================================================
// private VM（パブリック IP なし・本ステップの主役）
// ============================================================
// パブリック IP を付けない。もし付けてしまうと、その IP 自身で外へ出られてしまい、
// 「NAT Gateway が無いと外へ出られない」という対比が成立しなくなる。
// 「受信の入口は無い（パブリック IP なし）が、送信の出口（NAT Gateway）はある」という
// 非対称（inbound と outbound は別物）を、この VM 1 台で確認する。

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

output bastionPublicIp string = publicIpBastion.properties.ipAddress
output bastionPrivateIp string = bastionPrivateIp
output privatePrivateIp string = nicPrivate.properties.ipConfigurations[0].properties.privateIPAddress
// private VM が外へ出るときに名乗る出口のパブリック IP（SNAT の確認に使う）。
output natGatewayPublicIp string = natPublicIp.properties.ipAddress
