// WAF ポリシー: Application Gateway に適用する「検査ルール」の本体。
// - policySettings.mode … Detection(検知＝ログのみ) / Prevention(防御＝実ブロック) を切り替える中心スイッチ
// - managedRules … OWASP マネージドルールセット（SQLi / XSS など Top 10 系を検出）
// デプロイ後は再デプロイせず `az ... waf-policy policy-setting update --mode` でも mode を出し入れできる。

@description('Location for all resources.')
param location string

@description('Name of the WAF policy')
param policyName string = 'waf-policy'

@description('WAF mode: Prevention(block) or Detection(log only)')
@allowed([
  'Prevention'
  'Detection'
])
param wafMode string = 'Prevention'

resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-04-01' = {
  name: policyName
  location: location
  properties: {
    policySettings: {
      state: 'Enabled'
      mode: wafMode
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
      ]
    }
  }
}

output policyId string = wafPolicy.id
