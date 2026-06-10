// 観測基盤: Log Analytics ワークスペース。
// Front Door の診断設定（frontdoor.bicep 側で構成）から WAF ログ／アクセスログを送り、
// Detection モードで「ブロックはせずログだけ残る」様子、Prevention で 429 を返した様子を後から確認できるようにする。

@description('Location for all resources.')
param location string

@description('Name of the Log Analytics workspace')
param workspaceName string = 'log-edge'

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// 診断設定が要求するのはワークスペースの ARM リソース ID（GUID の customerId ではない）
output workspaceId string = workspace.id
