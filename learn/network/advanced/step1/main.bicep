// Step1 (advanced): L7 を「守る」 — WAF と TLS 終端
// このファイルは "オーケストレータ" に徹し、各責務は modules/ 配下に分割する。
// （構成が大きくなるため、1 つの巨大ファイルにせず役割ごとにモジュール化している）

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Admin username for the backend VM')
param adminUsername string = 'azureuser'

@description('Admin password for the backend VM')
@secure()
param adminPassword string = newGuid()

@description('Base64-encoded PFX certificate data for TLS termination (justfile が自己署名証明書から生成して渡す)')
@secure()
param certData string

@description('Password for the PFX certificate')
@secure()
param certPassword string

@description('WAF mode at deploy time: Prevention(実ブロック) or Detection(ログのみ)')
@allowed([
  'Prevention'
  'Detection'
])
param wafMode string = 'Prevention'

// 1. ネットワーク基盤（VNet・サブネット・NSG・Public IP）
module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
  }
}

// 2. 観測基盤（Log Analytics）。WAF ログの確認に使う
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
  }
}

// 3. バックエンド VM（Nginx。どのパスでも 200 を返す = WAF を通過したか判定しやすくする）
module backend 'modules/backend.bicep' = {
  name: 'backend'
  params: {
    location: location
    subnetId: network.outputs.backendSubnetId
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

// 4. WAF ポリシー（OWASP ルールセット。mode で Detection/Prevention を切替）
module wafPolicy 'modules/waf-policy.bicep' = {
  name: 'waf-policy'
  params: {
    location: location
    wafMode: wafMode
  }
}

// 5. Application Gateway (WAF_v2)。HTTPS リスナーで TLS 終端し、WAF ポリシーを適用
module appgw 'modules/appgw.bicep' = {
  name: 'appgw'
  params: {
    location: location
    appgwSubnetId: network.outputs.appgwSubnetId
    publicIpId: network.outputs.publicIpId
    backendIp: backend.outputs.privateIp
    wafPolicyId: wafPolicy.outputs.policyId
    certData: certData
    certPassword: certPassword
    workspaceId: monitoring.outputs.workspaceId
  }
}

output appGatewayPublicIp string = network.outputs.publicIpAddress
