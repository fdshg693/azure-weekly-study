// Azure Cache for Redis。一覧キャッシュ用。学習向けに最小 SKU(Basic C0)。

@description('リージョン')
param location string

@description('Redis 名（グローバル一意・小文字）')
param redisName string

param tags object = {}

resource redis 'Microsoft.Cache/redis@2024-11-01' = {
  name: redisName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'Basic'
      family: 'C'
      capacity: 0
    }
    // 非 SSL ポート(6379)は閉じ、TLS(6380)のみ。アプリは REDIS_SSL=true で接続。
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
  }
}

output hostName string = redis.properties.hostName
output sslPort int = redis.properties.sslPort
@secure()
output primaryKey string = redis.listKeys().primaryKey
