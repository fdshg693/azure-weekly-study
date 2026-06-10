// Azure Front Door (Standard) — グローバルな L7 エッジ入口。
//  - エンドポイント(*.azurefd.net)は世界中の PoP にエニーキャストで広告され、ユーザーは「最寄りのエッジ」で受け止められる。
//  - オリジングループ＋オリジンで実バックエンド（このステップでは VM の公開 FQDN）へ転送する。
//  - securityPolicy で WAF ポリシー（レート制限）をエンドポイントに適用する。
//  - 診断設定で WAF/アクセスログを Log Analytics へ送る。
// step9/10 が「リージョン内」の分散だったのに対し、Front Door は「グローバル・エッジ」での分散と防御。

@description('Location for all resources (Front Door は Global リソース。location は metadata 用)')
param location string = 'Global'

@description('Name of the Front Door profile')
param profileName string = 'afd-edge'

@description('Name of the Front Door endpoint')
param endpointName string = 'edge-endpoint'

@description('Origin host (オリジン VM の公開 FQDN)')
param originHost string

@description('Front Door WAF policy resource id to associate')
param wafPolicyId string

@description('Log Analytics workspace resource id for diagnostics')
param workspaceId string

resource profile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: profileName
  location: location
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
}

// エニーキャストで広告されるグローバルエンドポイント（hostName は <endpoint>-<hash>.z01.azurefd.net 形式）
resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  parent: profile
  name: endpointName
  location: location
  properties: {
    enabledState: 'Enabled'
  }
}

// オリジングループ: ヘルスプローブで「生きているオリジン」だけに振り分ける（step9 の LB プローブのグローバル版）
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = {
  parent: profile
  name: 'origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'GET'
      probeProtocol: 'Http'
      probeIntervalInSeconds: 100
    }
  }
}

// オリジン本体。VM の公開 FQDN へ HTTP(80) で転送する。
resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  parent: originGroup
  name: 'origin-vm'
  properties: {
    hostName: originHost
    httpPort: 80
    httpsPort: 443
    originHostHeader: originHost
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: false
  }
}

// ルート: 全パス(/*)をオリジングループへ。HTTP で転送（オリジンは 80 で待ち受け）。
resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = {
  parent: endpoint
  name: 'route-default'
  dependsOn: [
    origin
  ]
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Disabled'
    enabledState: 'Enabled'
  }
}

// セキュリティポリシー: WAF ポリシー（レート制限）をエンドポイントのドメインに紐付ける
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2023-05-01' = {
  parent: profile
  name: 'security-policy'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicyId
      }
      associations: [
        {
          domains: [
            {
              id: endpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

// 診断設定: WAF ログ（レート制限の検知/ブロック）とアクセスログを Log Analytics へ送る
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'afd-diag'
  scope: profile
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'FrontDoorAccessLog'
        enabled: true
      }
      {
        category: 'FrontDoorWebApplicationFirewallLog'
        enabled: true
      }
    ]
  }
}

output endpointHostName string = endpoint.properties.hostName
