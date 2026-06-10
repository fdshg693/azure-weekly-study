@description('Location for all resources.')
param location string = resourceGroup().location

@description('Admin username for the VM')
param adminUsername string = 'azureuser'

@description('Admin password for the VM (auto-generated; we connect via Run Command, not SSH, so it is never used interactively)')
@secure()
param adminPassword string = newGuid()

@description('Globally-unique storage account name (lowercase, <=24 chars). Auto-derived from the resource group id.')
param storageAccountName string = 'stpl${uniqueString(resourceGroup().id)}'

// ============================================================
// このステップの主役：PaaS へ「プライベート IP」で到達する = Private Endpoint / Private Link
// ============================================================
// Step1〜7 で扱ってきたのは「自分で建てた VM 同士」の通信だった。
// 現実には、ストレージやデータベースのような **マネージドサービス（PaaS）** にも通信する。
// それらは既定で「公衆インターネット上の公開エンドポイント」を持つ（例: <account>.blob.core.windows.net）。
//
// 本ステップは、その PaaS へ **インターネットを経由せず、VNet 内のプライベート IP で** 到達する。
//   - サービスの実体に対して、自分のサブネット内に **NIC（=Private Endpoint）** を 1 枚生やす。
//     その NIC が VNet 内のプライベート IP（例 10.0.1.x）を持ち、PaaS への入口になる。
//   - 公開エンドポイントと同じ FQDN（<account>.blob.core.windows.net）を、
//     **Private DNS Zone（privatelink.blob.core.windows.net）** で **そのプライベート IP に解決**させる。
//     → アプリは URL を一切変えずに、名前解決の向き先だけが「公開 IP → プライベート IP」に変わる。
//   - さらにサービス側の **公開アクセスを無効化**（publicNetworkAccess: Disabled）して、
//     「公衆インターネットからの入口を閉じ、プライベート経路だけを開ける」を成立させる。
//
// ポイント（＝学びどころ）:
//   - Step7 で学んだ「名前 → IP の対応表」がそのまま効く。違いは “向き先がプライベート IP” という点。
//     同じ公開 FQDN が、Private DNS Zone のリンク有無で「プライベート IP / 公開 IP」を行き来する
//     （justfile の unlink / link。Step7 の名前解決の切り分けと同じ手法）。
//   - 「公開を閉じる（publicNetworkAccess）」と「プライベートで開ける（Private Endpoint）」は別の操作。
//     disable-public / enable-public で出し入れして、その独立性を体感する。

// ============================================================
// NSG（VM サブネット用。最小限）
// ============================================================
// 検証は Azure VM Run Command（VM 上でコマンド実行）で行うので、外部からの inbound は不要。
// 既定の AllowVnetInBound で PE への VNet 内通信は通る。ここでは明示的に VNet 内通信だけ許可しておく。
resource nsgVm 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-vm'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-VNet-Inbound'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
    ]
  }
}

// ============================================================
// VNet（PE 用サブネットと VM 用サブネットを分ける）
// ============================================================
// - snet-pe : Private Endpoint の NIC を置くサブネット（ここに PaaS への入口が生える）
// - snet-vm : PaaS へアクセスする VM を置くサブネット
// 役割が違うので分けておくと「PE はネットワーク上どこにいるのか」が見えやすい。
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-privatelink'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: '10.0.1.0/24'
          // Private Endpoint を置くサブネットでは、PE 向けのネットワークポリシーを無効化するのが定石。
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-vm'
        properties: {
          addressPrefix: '10.0.2.0/24'
          networkSecurityGroup: {
            id: nsgVm.id
          }
        }
      }
    ]
  }
}

// ============================================================
// 接続先の PaaS：Storage Account（blob）
// ============================================================
// publicNetworkAccess: 'Disabled' … 公衆インターネット上の公開エンドポイントを最初から閉じる。
//   → このアカウントへは「Private Endpoint 経由（プライベート IP）」でしか到達できない状態にする。
//     （justfile の enable-public / disable-public でこの扉を出し入れできる）
// allowBlobPublicAccess: false … 匿名公開も禁止（最小権限）。
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

// ============================================================
// Private DNS Zone（PaaS の公開 FQDN を “プライベート IP” に解決させる専用ゾーン）
// ============================================================
// blob の Private Endpoint には、決まった名前のゾーン privatelink.blob.core.windows.net を使う
// （environment().suffixes.storage = 'core.windows.net'）。
// 公開 FQDN <account>.blob.core.windows.net は、内部的に
//   <account>.blob.core.windows.net → CNAME → <account>.privatelink.blob.core.windows.net
// という形を取り、このゾーンがリンクされた VNet 内では、その privatelink 名が
// Private Endpoint のプライベート IP（A レコード）に解決される。
// → 結果として、URL を変えずに「公開 IP → プライベート IP」へ向き先が変わる。
resource blobZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
}

// ゾーンと VNet の「リンク」。これが無いと VNet からこのゾーンは見えず、公開 FQDN は
// 公衆 DNS の答え（=公開 IP）に解決される。Step7 と同じく、このリンクの出し入れで
// 「プライベート IP に解決させているのは Private DNS Zone だ」と切り分けられる（justfile の unlink/link）。
//   - registrationEnabled: false … 自動登録は不要（A レコードは下の DNS Zone Group が作る）。
resource blobZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: blobZone
  name: 'link-to-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// ============================================================
// Private Endpoint（PaaS への “入口” = 自分のサブネットに生やす NIC）
// ============================================================
// privateLinkServiceConnections で「どのサービスの、どのサブリソース（groupId）に繋ぐか」を指定する。
//   - privateLinkServiceId : 繋ぎ先のリソース（ここでは storage アカウント）
//   - groupIds: ['blob']   : そのうち blob サービスへの接続（file/queue/table なら別 groupId）
// デプロイされると、snet-pe 内にプライベート IP を持つ NIC が 1 枚でき、それが blob への入口になる。
resource blobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-blob'
  location: location
  properties: {
    subnet: {
      id: vnet.properties.subnets[0].id // snet-pe
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-blob-conn'
        properties: {
          privateLinkServiceId: storage.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

// ============================================================
// Private DNS Zone Group（PE の IP を上記ゾーンへ “自動登録” する糊）
// ============================================================
// これが、Private Endpoint のプライベート IP を privatelink.blob.core.windows.net ゾーンに
// A レコードとして自動で作る/維持する仕組み。手で A レコードを書く必要がなくなり、
// PE の IP が変わっても追従する。Step7 の「手動レコード」に対する、PE 専用の自動連携。
resource blobPeDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: blobPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob-config'
        properties: {
          privateDnsZoneId: blobZone.id
        }
      }
    ]
  }
}

// ============================================================
// PaaS へアクセスする VM（パブリック IP なし。検証は Run Command）
// ============================================================
resource nicVm 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-vm'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.0.2.4'
          subnet: {
            id: vnet.properties.subnets[1].id // snet-vm
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm'
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
          id: nicVm.id
        }
      ]
    }
  }
}

output storageAccountName string = storage.name
output blobFqdn string = '${storage.name}.blob.${environment().suffixes.storage}'
output privateDnsZone string = blobZone.name
output peName string = blobPrivateEndpoint.name
