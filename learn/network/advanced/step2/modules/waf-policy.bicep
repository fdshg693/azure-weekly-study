// Front Door 用 WAF ポリシー（エッジ側の WAF）。
// step1 は Application Gateway（リージョン内）の WAF だったが、ここでは Front Door（グローバル・エッジ）の WAF。
// このステップの核心は「体積型（フラッディング）攻撃の緩和」なので、レート制限ルール(RateLimitRule)を1本だけ載せる。
//
// - policySettings.mode … Detection(検知＝ログのみ) / Prevention(防御＝実ブロック) を切り替える中心スイッチ
//   Prevention のとき、しきい値を超えた分のリクエストに 429(Too Many Requests) を返す。
//   Detection のとき、同じバーストでもブロックせず全て通す（ログだけ残る）。
// - sku は Front Door 本体と一致させる必要がある（Standard_AzureFrontDoor）。
//   ※ Standard ではマネージドルールセット(DRS)は使えず custom rule のみ。レート制限は custom rule なので Standard で動く。
//
// 注意: Front Door の WAF ポリシー名はハイフン不可（英数字のみ）。

@description('Name of the Front Door WAF policy (alphanumeric only — no hyphens)')
param policyName string = 'wafEdgePolicy'

@description('WAF mode: Prevention(block) or Detection(log only)')
@allowed([
  'Prevention'
  'Detection'
])
param wafMode string = 'Prevention'

@description('Rate limit threshold: requests per client IP within the duration window')
param rateLimitThreshold int = 30

@description('Rate limit window in minutes (1 or 5)')
@allowed([
  1
  5
])
param rateLimitDurationInMinutes int = 1

// Front Door の WAF ポリシーは Global リソース
resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2022-05-01' = {
  name: policyName
  location: 'Global'
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
      requestBodyCheck: 'Enabled'
    }
    customRules: {
      rules: [
        {
          // クライアント IP ごとに「1分あたり N リクエスト」を超えたら以後をブロックする
          name: 'RateLimitPerClientIp'
          enabledState: 'Enabled'
          priority: 100
          ruleType: 'RateLimitRule'
          rateLimitDurationInMinutes: rateLimitDurationInMinutes
          rateLimitThreshold: rateLimitThreshold
          matchConditions: [
            {
              // どんな URI にも '/' は含まれるので、全リクエストを計数対象にする
              matchVariable: 'RequestUri'
              operator: 'Contains'
              negateCondition: false
              matchValue: [
                '/'
              ]
              transforms: []
            }
          ]
          action: 'Block'
        }
      ]
    }
  }
}

output policyId string = wafPolicy.id
