// ============================================================================
// container/aci — コンテナグループ (複数コンテナ同居) の最小形 = sidecar
// ============================================================================
// ACI の Container Group は「1 台のホストに同居する複数コンテナ」を表す。
//   - 同じグループのコンテナは **localhost を共有**する (network namespace 共有)。
//   - ライフサイクル (起動/停止/課金) もグループ単位。
// ここでは web (nginx) + sidecar (web に localhost で叩きに行くだけ) の 2 つを同居させ、
// 「sidecar から http://localhost:80 で web に届く」＝同居コンテナはネットワークを共有する、を観察する。
//   → sidecar の logs に "[sidecar] reached web" が出れば成功 (task logs CONTAINER=sidecar)。

@description('デプロイ先リージョン')
param location string = resourceGroup().location

@description('リソース名プレフィックス')
@minLength(1)
@maxLength(12)
param prefix string = 'aci'

@description('一意性確保用サフィックス (FQDN の DNS ラベル)')
@minLength(2)
param suffix string = uniqueString(resourceGroup().id)

@description('ACR ログインサーバ (registry の出力)')
param acrLoginServer string

@description('pull するイメージ <repo>:<tag>')
param image string = 'web:v1'

@description('キーレス pull に使う消費者 UAMI のリソース ID')
param uamiResourceId string

var cgName = 'cg-${prefix}-sidecar'
var dnsLabel = toLower('${prefix}-sc-${suffix}')

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
    restartPolicy: 'Always'
    imageRegistryCredentials: [
      {
        server: acrLoginServer
        identity: uamiResourceId
      }
    ]
    ipAddress: {
      type: 'Public'
      dnsNameLabel: dnsLabel
      ports: [
        {
          protocol: 'TCP'
          port: 80
        }
      ]
    }
    containers: [
      // 主コンテナ: web を配信する (グループの 80 番として公開)。
      {
        name: 'web'
        properties: {
          image: '${acrLoginServer}/${image}'
          ports: [
            {
              protocol: 'TCP'
              port: 80
            }
          ]
          resources: {
            requests: {
              cpu: 1
              memoryInGB: 1
            }
          }
        }
      }
      // sidecar: 公開ポートは持たず、localhost 経由で web を叩いて結果をログに出すだけ。
      // 同じグループ＝同じ network namespace なので http://localhost:80 で隣の web に届く。
      {
        name: 'sidecar'
        properties: {
          image: '${acrLoginServer}/${image}'
          command: [
            '/bin/sh'
            '-c'
            'while true; do if wget -qO- http://localhost:80 >/dev/null 2>&1; then echo "[sidecar] reached web on localhost:80"; else echo "[sidecar] web not ready"; fi; sleep 10; done'
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

@description('web の到達用 FQDN')
output fqdn string = cg.properties.ipAddress.fqdn

@description('Container Group 名')
output cgName string = cg.name
