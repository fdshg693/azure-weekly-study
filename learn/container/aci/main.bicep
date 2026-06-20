// ============================================================================
// container/aci — Azure Container Instances (ACI) が主役の最小プロジェクト
// ============================================================================
// container トピックの Step 2。「もっとも素朴に “1 コンテナを Azure に載せる”」。
// オーケストレータ無し。Step 1 (registry) に上げたイメージを、registry が用意した
// 消費者 UAMI (AcrPull 済み) で **キーレス pull** し、Public IP / FQDN で到達する。
//
// このファイルで作るもの:
//   - Container Group (単一コンテナ web)   … ACI の最小単位。nginx 静的ページを配信
//   - Public IP + FQDN                      … 外から HTTP で到達できる入口
//   - UserAssigned Identity の割当          … registry の消費者 UAMI を assign
//   - imageRegistryCredentials.identity     … その UAMI で ACR から keyless pull
//
// 設計メモ:
//   - ACR / UAMI は **新規に作らず registry のデプロイ出力を参照**する
//     (acrLoginServer / uamiResourceId)。「各サービスが同じ ACR から引く」を貫く。
//   - 動的な値 (acrLoginServer / uamiResourceId / image) は registry のデプロイから
//     取り出して deploy 時に渡すので bicepparam は使わず scripts/deploy.ps1 で注入する。
//   - restartPolicy は実験で出し入れする主役パラメータ (Always / OnFailure / Never)。

@description('デプロイ先リージョン')
param location string = resourceGroup().location

@description('リソース名プレフィックス (DNS ラベル等に使う・英数字)')
@minLength(1)
@maxLength(12)
param prefix string = 'aci'

@description('一意性確保用サフィックス (FQDN の DNS ラベルに使う)')
@minLength(2)
param suffix string = uniqueString(resourceGroup().id)

@description('ACR ログインサーバ (registry デプロイの出力 acrLoginServer。例 acrreg....azurecr.io)')
param acrLoginServer string

@description('pull するイメージ <repo>:<tag> (registry に上げたもの)')
param image string = 'web:v1'

@description('キーレス pull に使う消費者 UAMI のリソース ID (registry の出力 uamiResourceId)')
param uamiResourceId string

@description('再起動ポリシー。Always=常に再起動 / OnFailure=異常終了時のみ / Never=しない')
@allowed([
  'Always'
  'OnFailure'
  'Never'
])
param restartPolicy string = 'Always'

@description('割り当て CPU コア数')
param cpu int = 1

@description('割り当てメモリ (GB)')
param memoryInGB int = 1

@description('リソースに付けるタグ')
param tags object = {
  Environment: 'Development'
  Project: 'ContainerAci'
  ManagedBy: 'Bicep'
}

var cgName = 'cg-${prefix}-web'
// FQDN は <dnsNameLabel>.<region>.azurecontainer.io。region 内で一意ならよい。
var dnsLabel = toLower('${prefix}-${suffix}')

resource cg 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: cgName
  location: location
  tags: tags
  // 消費者 UAMI を assign する。この ID 経由で ACR から pull する。
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiResourceId}': {}
    }
  }
  properties: {
    sku: 'Standard'
    osType: 'Linux'
    // 実験の主役。task deploy POLICY=... で出し入れする。
    restartPolicy: restartPolicy
    // ★キーレス pull: server だけ書き、identity に UAMI を指定する (パスワード無し)。
    //   admin user / SP のシークレットは一切使わない＝registry で学んだ keyless を実 pull で行使。
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
              cpu: cpu
              memoryInGB: memoryInGB
            }
          }
          // env 注入の最小例。az container show の containers[0].environmentVariables で見える。
          environmentVariables: [
            {
              name: 'GREETING'
              value: 'hello from ACI'
            }
          ]
        }
      }
    ]
  }
}

@description('到達用 FQDN (例 aci-xxxx.japaneast.azurecontainer.io)')
output fqdn string = cg.properties.ipAddress.fqdn

@description('割り当てられた Public IP')
output ip string = cg.properties.ipAddress.ip

@description('ブラウザ/curl で開く URL')
output url string = 'http://${cg.properties.ipAddress.fqdn}'

@description('Container Group 名 (az container show / logs の --name)')
output cgName string = cg.name
