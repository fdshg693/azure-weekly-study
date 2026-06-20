// ============================================================================
// マネージド PostgreSQL (PaaS) が主役の最小構成 — Flexible Server を 1 台立てて繋ぐ
// ============================================================================
// db トピック PLAN Step 1 (`simple`) の Bicep 実装。
// 「DB の運用 (パッチ/バックアップ/可用性) を Azure に任せる代わりに、何が制約に
// なるか」を体で覚えるための土台。まずは「立てて・繋いで・閉じている事を確かめる」。
//
// 作るもの (マネージド DB を動かすのに最低限必要な一式):
//   - PostgreSQL Flexible Server … 主役。パスワード認証 / パブリックエンドポイント
//   - Database (論理 DB)          … サーバーの中に作る 1 つの論理データベース
//
// ★ ファイアウォール規則は「あえて Bicep に書かない」。
//   作成直後は許可 IP が 1 つも無い = どこからも繋がらない (= マネージド DB は
//   デフォルトで閉じている)。justfile の allow-my-ip / deny-my-ip で自分の IP を
//   出し入れし、「足すと通る・外すと拒否される」因果を観察する (vm/simple の
//   NSG ルール出し入れと同じ型)。
//
// 認証は「パスワード認証」のみ (Entra 認証によるパスワードレス化は Step 2 で扱う)。
//
// デプロイは justfile (`just deploy`) 経由を推奨。パスワードは .env の PGPASSWORD
// を渡す。直接打つ場合:
//   az deployment group create -g rg-db-learn-simple \
//     --template-file main.bicep \
//     --parameters adminUsername=pgadmin adminPassword='<強いパスワード>'

// ============================================================================
// パラメータ
// ============================================================================

@description('全リソースのリージョン')
param location string = resourceGroup().location

@description('リソース名のプレフィックス (小文字・英数字とハイフン)')
@minLength(1)
@maxLength(20)
param prefix string = 'dbsimple'

@description('DB 管理者ユーザー名 (接続時の user)')
param adminUsername string = 'pgadmin'

@description('DB 管理者パスワード。justfile が .env の PGPASSWORD を渡す')
@secure()
param adminPassword string

@description('作成する論理データベース名')
param databaseName string = 'appdb'

@description('PostgreSQL のメジャーバージョン')
@allowed(['14', '15', '16'])
param postgresVersion string = '16'

@description('コンピュート SKU。学習用は最安クラスのバースト可能 (Burstable) で十分')
param skuName string = 'Standard_B1ms'

@description('SKU の階層。Burstable は普段低 CPU で安価、検証向き')
@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param skuTier string = 'Burstable'

@description('ストレージサイズ (GB)。最小は 32GB')
param storageSizeGB int = 32

@description('リソースに付けるタグ')
param tags object = {
  Environment: 'Development'
  Project: 'DbSimple'
  ManagedBy: 'Bicep'
}

// ============================================================================
// 名前 — Flexible Server 名はグローバル一意かつ小文字。RG の一意文字列を付ける。
// ============================================================================
var serverName = toLower('pg-${prefix}-${uniqueString(resourceGroup().id)}')

// ============================================================================
// PostgreSQL Flexible Server — 主役
//   - publicNetworkAccess: Enabled … パブリックエンドポイントを持つ。ただし
//     ファイアウォール規則が無いので「経路はあるが誰も通れない」初期状態になる。
//   - authConfig: パスワード認証のみ (Entra 認証は Step 2)。
// ============================================================================
resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: postgresVersion
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: storageSizeGB
    }
    backup: {
      // PITR (ポイントインタイムリストア) の保持期間。Step 4 で深掘りする土台。
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      // 学習用はゾーン冗長を切る (課金と起動時間を抑える)。可用性は発展ステップで。
      mode: 'Disabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    network: {
      // パブリックエンドポイントを使う。閉域化 (Private Endpoint) は Step 3。
      publicNetworkAccess: 'Enabled'
    }
  }
}

// ============================================================================
// Database — サーバーの中に作る 1 つの論理データベース
//   「サーバー > データベース > (スキーマ/テーブル)」の階層を体感する単位。
// ============================================================================
resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: pg
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// ============================================================================
// 出力 (justfile が各レシピで参照する)
// ============================================================================
@description('Flexible Server 名 (ファイアウォール規則の出し入れ等に使う)')
output serverName string = pg.name

@description('接続先ホスト名 (FQDN)。.env の PGHOST に書き込む')
output fqdn string = pg.properties.fullyQualifiedDomainName

@description('管理者ユーザー名 (接続の user)')
output adminUsername string = adminUsername

@description('論理データベース名 (接続の dbname)')
output databaseName string = database.name
