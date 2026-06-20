// 1 つの VPN Gateway（と専用 Public IP）。hub / onprem で 2 回呼ぶ。
//
// ポイント:
//   - gatewayType=Vpn / vpnType=RouteBased … BGP・VNet-to-VNet を使うには「ルートベース」必須
//     （ポリシーベースは静的セレクタのみで BGP 不可）。
//   - sku=VpnGw1 … BGP を使える最小 SKU。Basic SKU は BGP 非対応なので使わない。
//   - enableBgp=true ＋ bgpSettings.asn … この Gateway を BGP スピーカーにし、ASN を割り当てる。
//     BGP ピアリング用アドレスは GatewaySubnet 内から Azure が自動採番する（手動指定不要）。
//
// デプロイには 1 台あたり ~30 分かかる（VPN Gateway はプロビジョニングが重いリソース）。

@description('Location for the gateway.')
param location string

@description('Name of the VPN Gateway')
param name string

@description('Resource id of the GatewaySubnet to host the gateway')
param gatewaySubnetId string

@description('BGP ASN for this gateway. 対向ゲートウェイとは必ず異なる値にする')
param asn int

// VPN Gateway 用の Public IP（トンネルの外側エンドポイント）。Standard / Static。
resource pip 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: 'pip-${name}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource vng 'Microsoft.Network/virtualNetworkGateways@2023-04-01' = {
  name: name
  location: location
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    sku: {
      name: 'VpnGw1'
      tier: 'VpnGw1'
    }
    activeActive: false
    enableBgp: true
    ipConfigurations: [
      {
        name: 'gwIpConfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: gatewaySubnetId
          }
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
    bgpSettings: {
      asn: asn
    }
  }
}

output id string = vng.id
output name string = vng.name
