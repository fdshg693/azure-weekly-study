// Cosmos DB (NoSQL/SQL API)。users / messages コンテナを作る。
// 学習コストを抑えるため Serverless 課金モデルを使う（使った分だけ）。

@description('リージョン')
param location string

@description('Cosmos アカウント名（グローバル一意・小文字）')
param accountName string

@description('データベース名')
param databaseName string

param tags object = {}

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: accountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    // Serverless: 最小コストで学習向け
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  parent: account
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource usersContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = {
  parent: database
  name: 'users'
  properties: {
    resource: {
      id: 'users'
      partitionKey: {
        paths: [ '/id' ]
        kind: 'Hash'
      }
    }
  }
}

resource messagesContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = {
  parent: database
  name: 'messages'
  properties: {
    resource: {
      id: 'messages'
      partitionKey: {
        paths: [ '/pairKey' ]
        kind: 'Hash'
      }
    }
  }
}

output endpoint string = account.properties.documentEndpoint
output accountName string = account.name
// 学習用ショートカット：本来キーは output せず、デプロイ後に az で取得するのが安全。
// ここでは App Settings へ一気に流し込むため module 出力する。
@secure()
output primaryKey string = account.listKeys().primaryMasterKey
