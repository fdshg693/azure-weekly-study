// Step3 (advanced): オンプレ／拠点間をつなぐ — VPN Gateway / IPsec / BGP（PLAN の案1）
// このファイルは "オーケストレータ" に徹し、各責務は modules/ 配下に分割する。
//
// 構図（2 つの VNet で「2 つの拠点」を再現）:
//   [vnet-hub 10.0.0.0/16]  ==(IPsec トンネル / BGP で経路交換)==  [vnet-onprem 10.50.0.0/16]
//        VPN Gateway(vng-hub)                                          VPN Gateway(vng-onprem)
//        test VM 10.0.1.4                                              test VM 10.50.1.4
//
// basic/step2 のピアリング（同一クラウド内の私設配線）に対し、本ステップは「外（公衆網）を経由する
// 暗号化トンネル」。さらに basic/step3 の静的 UDR に対し、BGP で経路が自動伝播する点を対比する。

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Admin username for the test VMs')
param adminUsername string = 'azureuser'

@description('Admin password for the test VMs')
@secure()
param adminPassword string = newGuid()

@description('Pre-Shared Key (PSK) for the IPsec/IKE tunnel. 両方向の接続で同じ値を使う（justfile が必ず渡す）')
@secure()
param sharedKey string = ''

// ---- ASN（自律システム番号）。VNet-to-VNet の BGP では両端で必ず異なる ASN にする ----
// 65515 は Azure が既定で割り当てる ASN なので hub はそれを使い、onprem は別の私用 ASN を割り当てる。
var hubAsn = 65515
var onpremAsn = 65501

// 1. 拠点 A（Azure 側ハブ）: VNet(GatewaySubnet + workload) ＋ NSG ＋ テスト VM
module siteHub 'modules/site.bicep' = {
  name: 'site-hub'
  params: {
    location: location
    vnetName: 'vnet-hub'
    vnetCidr: '10.0.0.0/16'
    workloadCidr: '10.0.1.0/24'
    gatewayCidr: '10.0.255.0/27'
    vmName: 'vm-hub'
    vmPrivateIp: '10.0.1.4'
    peerAddressSpace: '10.50.0.0/16' // 対向拠点からの 80/ICMP を許可するために渡す
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

// 2. 拠点 B（検証用の "オンプレ" 代用）: 同構成をもう 1 セット
module siteOnprem 'modules/site.bicep' = {
  name: 'site-onprem'
  params: {
    location: location
    vnetName: 'vnet-onprem'
    vnetCidr: '10.50.0.0/16'
    workloadCidr: '10.50.1.0/24'
    gatewayCidr: '10.50.255.0/27'
    vmName: 'vm-onprem'
    vmPrivateIp: '10.50.1.4'
    peerAddressSpace: '10.0.0.0/16'
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

// 3. 拠点 A の VPN Gateway（VpnGw1 / RouteBased / BGP 有効）
module gwHub 'modules/gateway.bicep' = {
  name: 'gw-hub'
  params: {
    location: location
    name: 'vng-hub'
    gatewaySubnetId: siteHub.outputs.gatewaySubnetId
    asn: hubAsn
  }
}

// 4. 拠点 B の VPN Gateway（別 ASN）
module gwOnprem 'modules/gateway.bicep' = {
  name: 'gw-onprem'
  params: {
    location: location
    name: 'vng-onprem'
    gatewaySubnetId: siteOnprem.outputs.gatewaySubnetId
    asn: onpremAsn
  }
}

// 5. VNet-to-VNet 接続（IPsec トンネル＋BGP）。双方向なので 2 本作る。両端で sharedKey を一致させる。
module connHubToOnprem 'modules/connection.bicep' = {
  name: 'conn-hub-to-onprem'
  params: {
    location: location
    name: 'conn-hub-to-onprem'
    vng1Id: gwHub.outputs.id
    vng2Id: gwOnprem.outputs.id
    sharedKey: sharedKey
  }
}

module connOnpremToHub 'modules/connection.bicep' = {
  name: 'conn-onprem-to-hub'
  params: {
    location: location
    name: 'conn-onprem-to-hub'
    vng1Id: gwOnprem.outputs.id
    vng2Id: gwHub.outputs.id
    sharedKey: sharedKey
  }
}

output hubGatewayName string = gwHub.outputs.name
output onpremGatewayName string = gwOnprem.outputs.name
output hubVmName string = siteHub.outputs.vmName
output onpremVmName string = siteOnprem.outputs.vmName
output hubVmPrivateIp string = siteHub.outputs.vmPrivateIp
output onpremVmPrivateIp string = siteOnprem.outputs.vmPrivateIp
output hubAsn int = hubAsn
output onpremAsn int = onpremAsn
