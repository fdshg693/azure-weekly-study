// VNet-to-VNet 接続（= 2 つの VPN Gateway 同士を IPsec トンネルで結ぶ 1 本）。
// 双方向通信のため main.bicep から「hub→onprem」「onprem→hub」の 2 本を作る。
//
// ポイント:
//   - connectionType=Vnet2Vnet … 検証用に "オンプレ" を別 VNet＋別 Gateway で代用する形。
//     （本物のオンプレ相手なら connectionType=IPsec ＋ Local Network Gateway を使う）
//   - sharedKey … IKE の事前共有鍵(PSK)。両方向の接続で同じ値でなければトンネルが上がらない。
//   - enableBgp=true … このトンネル上で BGP セッションを張り、各 VNet のアドレス空間を動的に広告し合う。
//     これを false にすると経路は「接続が知っている VNet アドレス空間」から静的に入る（学習対象の対比点）。

@description('Location for the connection.')
param location string

@description('Name of the connection')
param name string

@description('Resource id of the local VPN Gateway (gateway1)')
param vng1Id string

@description('Resource id of the remote VPN Gateway (gateway2)')
param vng2Id string

@description('Pre-Shared Key (PSK) for IKE. 両方向で一致させる')
@secure()
param sharedKey string

resource connection 'Microsoft.Network/connections@2023-04-01' = {
  name: name
  location: location
  properties: {
    connectionType: 'Vnet2Vnet'
    virtualNetworkGateway1: {
      id: vng1Id
      properties: {}
    }
    virtualNetworkGateway2: {
      id: vng2Id
      properties: {}
    }
    sharedKey: sharedKey
    enableBgp: true
    routingWeight: 0
  }
}

output id string = connection.id
