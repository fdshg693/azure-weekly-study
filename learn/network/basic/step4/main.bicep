@description('Location for all resources.')
param location string = resourceGroup().location

@description('Admin username for the VMs')
param adminUsername string = 'azureuser'

@description('SSH public key (contents of bastion_key.pub). Installed on BOTH VMs so the same local private key authenticates each hop.')
param adminPublicKey string

@description('Your global (public) IP address. Only this IP is allowed to SSH into the bastion host.')
param myIp string

// 踏み台（bastion）の固定プライベート IP。
// private VM 側の NSG が「踏み台サブネットからの SSH のみ許可」を判定するのは
// サブネット範囲（10.0.0.0/24）だが、固定にしておくと挙動が追いやすい。
// （サブネットの先頭 .0〜.3 は Azure が予約しているため、最初に使えるのは .4）
var bastionPrivateIp = '10.0.0.4'

// 踏み台 VM に渡す cloud-init。
// ssh -J（ProxyJump）では、踏み台の sshd が「最終ホスト(private VM):22 への TCP 接続を中継する」
// 役割を担う。この中継（direct-tcpip フォワーディング）は sshd の AllowTcpForwarding が
// 有効である必要がある。Ubuntu の既定値は yes だが、踏み台の肝なので明示的に固定しておく。
// （private VM は普通の SSH を受けるだけで中継しないため、この設定は不要 → 踏み台にだけ適用する）
var bastionCloudInit = '''#cloud-config
write_files:
  - path: /etc/ssh/sshd_config.d/10-allow-tcp-forwarding.conf
    permissions: '0644'
    content: |
      # ProxyJump (ssh -J) の中継に必要。踏み台が最終ホストへの TCP 接続を転送できるようにする。
      AllowTcpForwarding yes
runcmd:
  - systemctl restart ssh
'''

// ============================================================
// NSG（各サブネットのアクセス制御）
// ============================================================

// --- 踏み台サブネット用 NSG（唯一インターネットに開く「入口」）---
// 踏み台はパブリック IP を持つ唯一の公開ホスト。
// ここを破られると内部へ波及するため、SSH の送信元を「自分のグローバル IP だけ」に絞る。
// （Step2 の「送信元の限定（最小権限）」を、入口そのものに適用する形）
resource nsgBastion 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
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
          // ここが踏み台の肝。'*'（どこからでも）にせず、自分の IP だけに限定する。
          sourceAddressPrefix: '${myIp}/32'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// --- private サブネット用 NSG（内部の保護対象・パブリック IP なし）---
// private VM への SSH は「踏み台サブネット（10.0.0.0/24）から」のものだけ許可する。
// インターネットからの直接 SSH は、そもそもパブリック IP が無いため到達不能だが、
// 経路上も「踏み台を経由した接続だけ」に絞ることで二重に守る。
resource nsgPrivate 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
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
          // 踏み台サブネットからの SSH のみ許可（最小権限）。
          // ProxyJump で踏み台を経由すると、private VM から見た送信元は踏み台の IP になる。
          sourceAddressPrefix: '10.0.0.0/24'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ============================================================
// VNet（1つの VNet を 2 サブネットに分ける: 公開ゾーン / 非公開ゾーン）
// ============================================================
// subnet-bastion: 踏み台（パブリック IP あり）を置く「公開ゾーン」
// subnet-private: 保護対象 VM（パブリック IP なし）を置く「非公開ゾーン」
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'vnet-bastion'
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
        }
      }
    ]
  }
}

// ============================================================
// 踏み台 VM（パブリック IP あり・唯一の入口）
// ============================================================

resource publicIpBastion 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: 'pip-bastion'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nicBastion 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-bastion'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          // 追いやすさのためプライベート IP を固定する。
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
      // ssh -J の中継に必要な AllowTcpForwarding を明示的に有効化する（cloud-init）。
      customData: base64(bastionCloudInit)
      // 踏み台は外部に開く入口なので、パスワード認証を無効化し公開鍵認証のみにする。
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
// private VM（パブリック IP なし・踏み台越しにしか入れない保護対象）
// ============================================================
// パブリック IP を付けないことで、SSH 接続が成功した場合に
// それが確実に「踏み台を経由したプライベート経路」であることを担保する（Step2/3 と同じ考え方）。

resource nicPrivate 'Microsoft.Network/networkInterfaces@2023-04-01' = {
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
      // 踏み台と同じ公開鍵を入れておく。ProxyJump では秘密鍵はローカルから出ないため、
      // 同じ鍵で両方のホップを認証できる。
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
