// ============================================================================
// container/aci — restartPolicy の因果を確かめる用の「わざと終了するコンテナ」
// ============================================================================
// main.bicep (常駐する web) とは別に、指定の終了コードで終わるコンテナを 1 つ立てる。
// restartPolicy と exitCode の組合せで「再起動するか」が変わるのを観察する:
//   - Always   : 成功(0)でも失敗(1)でも毎回再起動する
//   - OnFailure: 失敗(!=0)のときだけ再起動。成功(0)なら 1 回で終わる
//   - Never    : 何があっても再起動しない (1 回で Terminated)
// Ingress は不要なので Public IP は付けない (ipAddress を持たない＝外部到達なし)。

@description('デプロイ先リージョン')
param location string = resourceGroup().location

@description('リソース名プレフィックス')
@minLength(1)
@maxLength(12)
param prefix string = 'aci'

@description('ACR ログインサーバ (registry の出力)')
param acrLoginServer string

@description('pull するイメージ <repo>:<tag>')
param image string = 'web:v1'

@description('キーレス pull に使う消費者 UAMI のリソース ID')
param uamiResourceId string

@description('再起動ポリシー')
@allowed([
  'Always'
  'OnFailure'
  'Never'
])
param restartPolicy string = 'OnFailure'

@description('コンテナの終了コード (0=成功 / それ以外=失敗)')
param exitCode int = 1

var cgName = 'cg-${prefix}-restart'

resource cg 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: cgName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiResourceId}': {}
    }
  }
  properties: {
    sku: 'Standard'
    osType: 'Linux'
    restartPolicy: restartPolicy
    imageRegistryCredentials: [
      {
        server: acrLoginServer
        identity: uamiResourceId
      }
    ]
    // ipAddress 無し＝外部公開しない。終了コードだけ観察できればよい。
    containers: [
      {
        name: 'crasher'
        properties: {
          image: '${acrLoginServer}/${image}'
          // image 既定の nginx ではなく、5 秒生きてから指定コードで終了するだけのプロセスに差し替える。
          command: [
            '/bin/sh'
            '-c'
            'echo "[crasher] up; will exit ${exitCode} after 5s"; sleep 5; echo "[crasher] exiting ${exitCode}"; exit ${exitCode}'
          ]
          resources: {
            requests: {
              cpu: 1
              memoryInGB: 1
            }
          }
        }
      }
    ]
  }
}

@description('Container Group 名')
output cgName string = cg.name
