// Application Gateway (WAF_v2):
//  - HTTPS リスナー(443) + SSL 証明書で「入口での TLS 終端」を行う（復号して中身を検査できる状態にする）
//  - firewallPolicy で WAF ポリシーを適用し、復号後の HTTP の中身を OWASP ルールで検査する
//  - バックエンドへは HTTP(80) で転送（TLS オフロード）
//  - 診断設定で WAF ログ／アクセスログを Log Analytics へ送る

@description('Location for all resources.')
param location string

@description('Subnet id for the Application Gateway (dedicated)')
param appgwSubnetId string

@description('Public IP resource id')
param publicIpId string

@description('Backend VM private IP')
param backendIp string

@description('WAF policy resource id to associate')
param wafPolicyId string

@description('Base64-encoded PFX certificate data')
@secure()
param certData string

@description('Password for the PFX certificate')
@secure()
param certPassword string

@description('Log Analytics workspace resource id for diagnostics')
param workspaceId string

@description('Name of the Application Gateway')
param appgwName string = 'appgw-waf'

// Application Gateway の各構成要素は resourceId 相互参照で結ぶため、id を組み立てるヘルパ変数を用意する
var appgwId = resourceId('Microsoft.Network/applicationGateways', appgwName)

resource appgw 'Microsoft.Network/applicationGateways@2023-04-01' = {
  name: appgwName
  location: location
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 1
    }
    // WAF ポリシーをゲートウェイ全体に適用（旧 webApplicationFirewallConfiguration は使わない）
    firewallPolicy: {
      id: wafPolicyId
    }
    gatewayIPConfigurations: [
      {
        name: 'appgw-ip-config'
        properties: {
          subnet: {
            id: appgwSubnetId
          }
        }
      }
    ]
    // TLS 終端に使う証明書（justfile が生成した自己署名 PFX を base64 で受け取る）
    sslCertificates: [
      {
        name: 'appgw-cert'
        properties: {
          data: certData
          password: certPassword
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appgw-frontend-ip'
        properties: {
          publicIPAddress: {
            id: publicIpId
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port-443'
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'backend-pool'
        properties: {
          backendAddresses: [
            {
              ipAddress: backendIp
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'http-settings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 20
        }
      }
    ]
    // HTTPS リスナー: フロントエンド 443 で受け、証明書で TLS 終端する
    httpListeners: [
      {
        name: 'https-listener'
        properties: {
          frontendIPConfiguration: {
            id: '${appgwId}/frontendIPConfigurations/appgw-frontend-ip'
          }
          frontendPort: {
            id: '${appgwId}/frontendPorts/port-443'
          }
          protocol: 'Https'
          sslCertificate: {
            id: '${appgwId}/sslCertificates/appgw-cert'
          }
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'https-rule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: '${appgwId}/httpListeners/https-listener'
          }
          backendAddressPool: {
            id: '${appgwId}/backendAddressPools/backend-pool'
          }
          backendHttpSettings: {
            id: '${appgwId}/backendHttpSettingsCollection/http-settings'
          }
        }
      }
    ]
  }
}

// 診断設定: WAF ログ（検知/ブロックの記録）とアクセスログを Log Analytics へ送る
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'appgw-diag'
  scope: appgw
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'ApplicationGatewayAccessLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayFirewallLog'
        enabled: true
      }
    ]
  }
}
