@description('Location for all resources.')
param location string = resourceGroup().location

@description('Admin username for the VMs')
param adminUsername string = 'azureuser'

@description('Admin password for the spoke VM')
@secure()
param adminPassword string = newGuid()

// 出口で「許可する宛先 FQDN」。この 2 つだけ外へ出られる（それ以外はファイアウォールが遮断）。
// api.ipify.org は「外から見た送信元 IP」を返すので、SNAT（出口がファイアウォールの公開 IP に
// 集約されること）の確認にも使う。
@description('FQDNs that the spoke is allowed to reach (everything else is blocked).')
param allowedFqdns array = [
  'api.ipify.org'
  'ifconfig.me'
]

// ============================================================
// このステップの主題
// ============================================================
// Step3 では「自前の中継 VM（NVA）」を手組みして spoke 間通信を成立させた。
// Step5 では「NAT Gateway」で private VM の egress（外向き）を 1 つの公開 IP に集約した（ただし無検査）。
// 本ステップは、その発展として「スポークが勝手に外へ出るのではなく、ハブの 1 か所
// （Azure Firewall）を必ず経由させ、許可した FQDN だけ外へ出す（検査・制御する）」構成を作る。
//
//   - 各スポークの UDR で 0.0.0.0/0（=すべての外向き）を Firewall のプライベート IP に向ける
//     （= 強制トンネリング。出口をハブの 1 か所に矯正する）
//   - Firewall は「アプリケーションルール」で許可ドメインだけ通し、それ以外は拒否
//   - 出口を通った通信の送信元は Firewall の公開 IP に集約（SNAT）される
//
// Step3 の自前 NVA との違い：NVA は OS の ip_forward でパケットを素通しするだけ（無検査）。
// Azure Firewall はマネージドで、ステートフルに中身（宛先 FQDN 等）を見て許可/拒否できる。
// Step5 の NAT Gateway との違い：NAT Gateway は「出口の集約（SNAT）」専用で、誰がどこへ
// 出るかは検査しない。Firewall は「集約 + 検査・制御」を兼ねる。

// ============================================================
// NSG（スポークのワークロード用サブネット）
// ============================================================
// 本ステップの主役は「外向き（egress）の検査」なので、inbound は最小限。
// スポーク VM はパブリック IP を持たず、検証は az vm run-command（プラットフォーム経由）で行うため、
// インターネットからの inbound 許可は不要。VNet 内の管理用に SSH/ICMP だけ開けておく。
resource nsgWorkload 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-workload'
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
// ハブ VNet（Azure Firewall を置く）
// ============================================================
// Azure Firewall は予約名のサブネット「AzureFirewallSubnet」に置く必要がある（/26 以上）。
// （Application Gateway の専用サブネット（Step10）と同じく、専用サブネットを要求するマネージド機器）
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
        // 予約名・/26 以上が必須。NSG/UDR は付けられない（付けない）。
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: '10.0.1.0/26'
        }
      }
    ]
  }
}

// ============================================================
// Azure Firewall の公開 IP（出口として名乗るアドレス）
// ============================================================
// スポークの外向き通信は、ここに集約（SNAT）される。Standard SKU・Static が必須。
resource fwPublicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: 'pip-azfw'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ============================================================
// ファイアウォールポリシー（検査・制御のルールを定義）
// ============================================================
// Azure Firewall 本体と「ルール（何を許可/拒否するか）」は分離されている。
// ポリシーに書いたルールを Firewall が適用する。
resource fwPolicy 'Microsoft.Network/firewallPolicies@2023-04-01' = {
  name: 'fw-policy'
  location: location
  properties: {
    sku: {
      tier: 'Standard'
    }
  }
}

// アプリケーションルール：宛先 FQDN（ドメイン名）で許可/拒否を判断する。
// HTTPS では SNI（接続先サーバ名）を、HTTP では Host ヘッダを見て一致判定する。
// ここで許可した FQDN 以外への外向きはすべて拒否される（既定の拒否）。
resource fwRuleGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-04-01' = {
  parent: fwPolicy
  name: 'app-rule-group'
  properties: {
    priority: 100
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'allow-fqdn'
        priority: 100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'allow-allowed-fqdns'
            // 送信元はスポーク VNet のみ（最小権限）。
            sourceAddresses: [
              '10.1.0.0/16'
            ]
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
              {
                protocolType: 'Http'
                port: 80
              }
            ]
            targetFqdns: allowedFqdns
          }
        ]
      }
    ]
  }
}

// ============================================================
// Azure Firewall 本体
// ============================================================
// AzureFirewallSubnet に配置し、ポリシー（fwPolicy）を適用する。
// firewallPolicy の中身（ルール）が先に存在している必要があるため dependsOn でルール群を待つ。
resource firewall 'Microsoft.Network/azureFirewalls@2023-04-01' = {
  name: 'azfw'
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    firewallPolicy: {
      id: fwPolicy.id
    }
    ipConfigurations: [
      {
        name: 'fw-ipconfig'
        properties: {
          subnet: {
            id: vnetHub.properties.subnets[0].id
          }
          publicIPAddress: {
            id: fwPublicIp.id
          }
        }
      }
    ]
  }
  dependsOn: [
    fwRuleGroup
  ]
}

// Firewall がスポークから見た next hop（プライベート IP）。UDR の宛先に使う。
// AzureFirewallSubnet（10.0.1.0/26）から動的に割り当てられるため、ここで参照して固定的に扱う。
var firewallPrivateIp = firewall.properties.ipConfigurations[0].properties.privateIPAddress

// ============================================================
// ルートテーブル（UDR）：スポークの「外向きすべて」を Firewall へ向ける
// ============================================================
// 0.0.0.0/0（=デフォルトルート＝あらゆる外向き）の next hop を Firewall のプライベート IP にする。
// これにより、スポークが直接インターネットへ出る既定の経路を上書きし、必ずハブの Firewall を
// 経由させる（= egress の中央集約 / 強制トンネリング）。
// Step3 の UDR は「特定スポーク宛て」を NVA に向けたが、ここでは「全外向き」を Firewall に向ける点が違う。
resource rtSpoke 'Microsoft.Network/routeTables@2023-04-01' = {
  name: 'rt-spoke'
  location: location
  properties: {
    routes: [
      {
        name: 'default-to-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
}

// ============================================================
// スポーク VNet（ワークロード VM を置く）
// ============================================================
// workload サブネットに UDR（rt-spoke）を関連付け、外向きを Firewall に矯正する。
// defaultOutboundAccess: false にして、「UDR を外したら本当に外へ出られなくなる」状態にする。
// （Step5 と同じ考え方。Azure 暗黙の共有 SNAT を消し、出口を Firewall 経由だけにする）
resource vnetSpoke 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'vnet-spoke'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-workload'
        properties: {
          addressPrefix: '10.1.0.0/24'
          networkSecurityGroup: {
            id: nsgWorkload.id
          }
          routeTable: {
            id: rtSpoke.id
          }
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

// ============================================================
// VNet ピアリング（hub ↔ spoke）
// ============================================================
// スポークの外向きトラフィックはハブの Firewall を宛先（next hop）とするため、両 VNet を接続する。
resource peeringHubToSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  parent: vnetHub
  name: 'peering-hub-to-spoke'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnetSpoke.id
    }
  }
}

resource peeringSpokeToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  parent: vnetSpoke
  name: 'peering-spoke-to-hub'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnetHub.id
    }
  }
}

// ============================================================
// スポークのワークロード VM（外向き検査の検証対象・パブリック IP なし）
// ============================================================
// パブリック IP を付けない。付けるとその IP で直接外へ出られてしまい、「Firewall を経由して
// いる／許可 FQDN だけ通る」という対比が成立しなくなる。
// 検証はインターネット経由ではなく az vm run-command（Azure プラットフォーム経由）で VM 内から
// curl を実行する。Ubuntu イメージには curl が同梱されている。
resource nicWorkload 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nic-workload'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnetSpoke.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource vmWorkload 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'vm-workload'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'vm-workload'
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
          id: nicWorkload.id
        }
      ]
    }
  }
}

// Firewall の公開 IP（出口の SNAT アドレス）。許可 FQDN への curl 結果がこの IP と一致すれば
// 「外向きが Firewall に集約されている」ことの証拠になる。
output firewallPublicIp string = fwPublicIp.properties.ipAddress
// Firewall のプライベート IP（スポーク UDR の next hop）。show-routes での確認に使う。
output firewallPrivateIp string = firewallPrivateIp
output workloadPrivateIp string = nicWorkload.properties.ipConfigurations[0].properties.privateIPAddress
