// V2: Azure Communication Services (Email)。検証メールの実送信に使う。
// 学習をすぐ始められるよう Azure 管理ドメイン（*.azurecomm.net）を作る。
// 独自ドメイン（SPF/DKIM 検証）は深掘りの任意テーマなのでここでは扱わない。
//
// 構成は 3 リソース:
//   1) Email Service（メール基盤）
//   2) その配下の Azure 管理ドメイン
//   3) Communication Service（SDK が接続文字列で叩く窓口。ドメインを紐付ける）

@description('リージョン。ACS データ所在地に使う（メタデータ上のリージョン）')
param location string = 'global'

@description('データ所在地（Email/ACS は dataLocation を要求する）')
param dataLocation string = 'United States'

@description('Email Service 名（グローバル一意・小文字推奨）')
param emailServiceName string

@description('Communication Service 名')
param communicationName string

param tags object = {}

resource emailService 'Microsoft.Communication/emailServices@2023-04-01' = {
  name: emailServiceName
  location: location
  tags: tags
  properties: {
    dataLocation: dataLocation
  }
}

// Azure 管理ドメイン（DoNotReply@<random>.azurecomm.net が即使える）。
resource managedDomain 'Microsoft.Communication/emailServices/domains@2023-04-01' = {
  parent: emailService
  name: 'AzureManagedDomain'
  location: location
  tags: tags
  properties: {
    domainManagement: 'AzureManaged'
    userEngagementTracking: 'Disabled'
  }
}

// Communication Service 本体。上で作ったドメインを紐付ける。
resource communication 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: communicationName
  location: location
  tags: tags
  properties: {
    dataLocation: dataLocation
    linkedDomains: [
      managedDomain.id
    ]
  }
}

// SDK 認証に使う接続文字列。本来は秘密情報（Key Vault 管理が望ましい）。
@secure()
output connectionString string = communication.listKeys().primaryConnectionString
// 送信元アドレス（DoNotReply@<azurecomm ドメイン>）。fromSenderDomain は *.azurecomm.net。
output senderAddress string = 'DoNotReply@${managedDomain.properties.fromSenderDomain}'
output senderDomain string = managedDomain.properties.fromSenderDomain
