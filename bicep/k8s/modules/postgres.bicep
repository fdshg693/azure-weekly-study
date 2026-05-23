@description('Azure リソースをデプロイするリージョン')
param location string

@description('PostgreSQL フレキシブルサーバー名 (小文字英数字とハイフン、グローバル一意)')
param pgName string

@description('管理者ユーザー名')
param adminUser string

@description('管理者パスワード')
@secure()
param adminPassword string

@description('PostgreSQL のメジャーバージョン')
param pgVersion string

@description('リソースに適用するタグ')
param tags object

resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: pgName
  location: location
  // POC なので最小スペック (Burstable / B1ms)。本番は GeneralPurpose や HA を検討。
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: adminUser
    administratorLoginPassword: adminPassword
    version: pgVersion
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
  tags: tags
}

// 記事の `--public-access 0.0.0.0` 相当:
// 開始・終了アドレスをともに 0.0.0.0 にすると「Azure 内の任意のサービスからの
// アクセスを許可」になる。AKS も同じ Azure 内なので Pod から接続できる。
// (POC 向けの割り切り。本番は VNet 統合 / Private Endpoint にする)
resource allowAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-06-01-preview' = {
  parent: pg
  name: 'AllowAllAzureServicesAndResources'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output pgName string = pg.name
output pgFqdn string = pg.properties.fullyQualifiedDomainName
output pgAdminUser string = adminUser
