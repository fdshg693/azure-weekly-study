// ============================================================================
// VM (IaaS) が主役の最小構成 — Linux VM を 1 台立てて SSH で入る
// ============================================================================
// vm トピック PLAN Step 1 (`simple`) の Bicep 実装。
// 「OS から自分で面倒を見る代わりに何が自由になるか」を体で覚えるための土台。
//
// 作るもの (VM 1 台を動かすのに最低限必要な一式):
//   - VNet / Subnet            … VM が所属するネットワーク
//   - NSG                      … サブネットに付ける受信フィルタ (SSH=22 を許可)
//   - Public IP                … 外から VM へ届くための住所
//   - NIC                      … VM をサブネット・Public IP につなぐ仮想 NIC
//   - Linux VM (Ubuntu)        … 主役。SSH "鍵" 認証 (パスワードレス)
//
// パスワード認証は無効化し、公開鍵だけでログインできるようにしている。
//
// デプロイは justfile (`just deploy`) 経由を推奨。手元の公開鍵を adminPublicKey
// として渡す。直接打つ場合:
//   az deployment group create -g rg-vm-learn-simple \
//     --template-file main.bicep \
//     --parameters adminPublicKey="$(Get-Content ~/.ssh/id_ed25519.pub -Raw)"

// ============================================================================
// パラメータ
// ============================================================================

@description('全リソースのリージョン')
param location string = resourceGroup().location

@description('リソース名のプレフィックス')
@minLength(1)
@maxLength(16)
param prefix string = 'simple'

@description('VM の管理者ユーザー名 (SSH のログインユーザー)')
param adminUsername string = 'azureuser'

@description('SSH 公開鍵 (例: ~/.ssh/id_ed25519.pub の中身)。これだけでログインする')
param adminPublicKey string

@description('VM サイズ。学習用は最小クラスで十分')
param vmSize string = 'Standard_B1s'

@description('Public IP の SKU と払い出し方式。Basic+Dynamic にすると deallocate で IP が解放され、再起動で変わる様子を観察できる (Standard は Static のみ)')
@allowed(['Basic', 'Standard'])
param publicIpSku string = 'Basic'

@description('Public IP の払い出し方式。Dynamic だと deallocate 時に解放される')
@allowed(['Dynamic', 'Static'])
param publicIpAllocation string = 'Dynamic'

@description('リソースに付けるタグ')
param tags object = {
  Environment: 'Development'
  Project: 'VmSimple'
  ManagedBy: 'Bicep'
}

// ============================================================================
// 名前
// ============================================================================
var names = {
  vnet: 'vnet-${prefix}'
  subnet: 'subnet-${prefix}'
  nsg: 'nsg-${prefix}'
  pip: 'pip-${prefix}'
  nic: 'nic-${prefix}'
  vm: 'vm-${prefix}'
}

// ============================================================================
// NSG — サブネットに付ける受信フィルタ。初期状態は SSH(22) のみ許可。
// 80 番 (HTTP) は justfile の open-http レシピで後から足す/削る (因果実験)。
// ============================================================================
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: names.nsg
  location: location
  tags: tags
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
    ]
  }
}

// ============================================================================
// VNet + Subnet (Subnet に NSG を関連付け)
// ============================================================================
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: names.vnet
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: names.subnet
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// ============================================================================
// Public IP — 外から VM へ届くための住所
// ============================================================================
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: names.pip
  location: location
  tags: tags
  sku: {
    name: publicIpSku
  }
  properties: {
    publicIPAllocationMethod: publicIpAllocation
  }
}

// ============================================================================
// NIC — VM をサブネットと Public IP につなぐ
// ============================================================================
resource nic 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: names.nic
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
          subnet: {
            id: vnet.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

// ============================================================================
// Linux VM (Ubuntu 22.04 LTS) — SSH 鍵認証のみ
// ============================================================================
resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: names.vm
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: names.vm
      adminUsername: adminUsername
      // パスワード認証を無効化し、公開鍵だけで入れるようにする (パスワードレス)
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
          id: nic.id
        }
      ]
    }
  }
}

// ============================================================================
// 出力 (justfile が各レシピで参照する)
// ============================================================================
@description('SSH ログインユーザー名')
output adminUsername string = adminUsername

@description('VM 名 (az vm start/stop/deallocate に使う)')
output vmName string = vm.name

@description('NSG 名 (NSG ルールの出し入れに使う)')
output nsgName string = nsg.name

@description('Public IP リソース名 (現在の IP を引くのに使う)')
output publicIpName string = publicIp.name

@description('デプロイ直後の Public IP。Dynamic の場合は deallocate→start で変わりうる')
output publicIpAddress string = publicIp.properties.ipAddress
