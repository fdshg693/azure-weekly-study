// Step2 (advanced): 可用性とエッジ防御 — Front Door / DDoS Protection（PLAN の案5）
// このファイルは "オーケストレータ" に徹し、各責務は modules/ 配下に分割する。
//
// 構図:
//   Internet → [Front Door (グローバルエッジ・WAF レート制限)] → [オリジン VM (NSG で Front Door だけ許可)]
// step1 がリージョン内の App Gateway WAF だったのに対し、本ステップはグローバルエッジでの受け止めと体積型攻撃の緩和。

@description('Location for all (regional) resources.')
param location string = resourceGroup().location

@description('Admin username for the origin VM')
param adminUsername string = 'azureuser'

@description('Admin password for the origin VM')
@secure()
param adminPassword string = newGuid()

@description('WAF mode at deploy time: Prevention(実ブロック) or Detection(ログのみ)')
@allowed([
  'Prevention'
  'Detection'
])
param wafMode string = 'Prevention'

// 1. ネットワーク基盤（VNet・サブネット・NSG[Front Door だけ許可]・DNS ラベル付き Public IP）
module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
  }
}

// 2. 観測基盤（Log Analytics）。Front Door の WAF ログ確認に使う
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
  }
}

// 3. オリジン VM（Nginx。どのパスでも 200 を返す = エッジ経由で届いたか判定しやすくする）
module origin 'modules/origin.bicep' = {
  name: 'origin'
  params: {
    location: location
    subnetId: network.outputs.originSubnetId
    publicIpId: network.outputs.publicIpId
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

// 4. Front Door WAF ポリシー（レート制限ルール。mode で Detection/Prevention を切替）
module wafPolicy 'modules/waf-policy.bicep' = {
  name: 'waf-policy'
  params: {
    wafMode: wafMode
  }
}

// 5. Front Door（グローバルエッジ入口）。オリジンへ転送し、WAF ポリシーを適用
module frontdoor 'modules/frontdoor.bicep' = {
  name: 'frontdoor'
  params: {
    originHost: network.outputs.originFqdn
    wafPolicyId: wafPolicy.outputs.policyId
    workspaceId: monitoring.outputs.workspaceId
  }
  dependsOn: [
    origin
  ]
}

output endpointHostName string = frontdoor.outputs.endpointHostName
output originFqdn string = network.outputs.originFqdn
output originPublicIp string = network.outputs.publicIpAddress
