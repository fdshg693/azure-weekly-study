# ============================================================================
# メインのリソース定義ファイル
# ============================================================================
# このファイルでは、実際にAzure上に作成するリソースを定義します

# ----------------------------------------------------------------------------
# リソースグループの作成
# ----------------------------------------------------------------------------
# リソースグループは、関連するAzureリソースをまとめて管理するコンテナです
resource "azurerm_resource_group" "example" {
  # name: リソースグループの名前
  # 命名規則: 英数字、アンダースコア、括弧、ハイフン、ピリオド使用可能
  # 推奨: 「rg-<プロジェクト名>-<環境>-<リージョン>」の形式
  name = "rg-storage-example"
  
  # location: リソースグループを作成するAzureリージョン
  # 主要なリージョン:
  #   - Japan East (東日本): 東京
  #   - Japan West (西日本): 大阪
  #   - East US, West Europe など
  location = "Japan East"
  
  # tags: リソースに付与するメタデータ（オプション）
  # コスト管理や整理に便利
  # tags = {
  #   Environment = "Development"
  #   Project     = "StorageExample"
  #   ManagedBy   = "Terraform"
  #   Owner       = "YourName"
  # }
}

# ----------------------------------------------------------------------------
# Storage Accountの作成
# ----------------------------------------------------------------------------
# Storage Accountは、Blob、File、Queue、Tableストレージを提供するAzureサービス
resource "azurerm_storage_account" "example" {
  # name: Storage Accountの名前（グローバルで一意である必要があります）
  # 命名規則: 小文字と数字のみ、3-24文字
  # 例: "mystorageacct123", "companydata2024"
  name = var.storage_account_name
  
  # resource_group_name: 所属するリソースグループ名
  # 他のリソースの属性を参照する場合: <resource_type>.<resource_name>.<attribute>
  resource_group_name = azurerm_resource_group.example.name
  
  # location: Storage Accountを作成するリージョン
  # リソースグループと同じリージョンにすることが一般的
  location = azurerm_resource_group.example.location
  
  # account_tier: ストレージアカウントのパフォーマンスティア
  # オプション:
  #   - Standard: 汎用的な用途、HDD ベース、コスト効率が良い
  #   - Premium: 高パフォーマンスが必要な場合、SSD ベース、高コスト
  #     (Premium を選択する場合、account_kind も指定する必要があります)
  account_tier = "Standard"
  
  # account_replication_type: データの冗長性/レプリケーション戦略
  # オプション:
  #   - LRS (Locally Redundant Storage): 同一データセンター内で3コピー、最安
  #   - GRS (Geo-Redundant Storage): プライマリリージョン+セカンダリリージョン、6コピー
  #   - RAGRS (Read-Access GRS): GRS + セカンダリリージョンへの読み取りアクセス
  #   - ZRS (Zone-Redundant Storage): 同一リージョンの3つの可用性ゾーンに分散
  #   - GZRS (Geo-Zone-Redundant Storage): ZRS + 別リージョンへのレプリケーション
  #   - RAGZRS (Read-Access GZRS): GZRS + セカンダリリージョンへの読み取りアクセス
  account_replication_type = "GRS"
  
  # account_kind: ストレージアカウントの種類（オプション、デフォルト: StorageV2）
  # オプション:
  #   - StorageV2: 汎用v2、最新機能をサポート（推奨）
  #   - Storage: 汎用v1（レガシー）
  #   - BlobStorage: Blobストレージ専用
  #   - FileStorage: Fileストレージ専用（Premium tierのみ）
  #   - BlockBlobStorage: Block Blob専用（Premium tierのみ）
  # account_kind = "StorageV2"
  
  # access_tier: Blobデータのアクセス頻度（オプション、account_kind が StorageV2 または BlobStorage の場合）
  # オプション:
  #   - Hot: 頻繁にアクセスされるデータ、高いストレージコスト、低いアクセスコスト
  #   - Cool: 低頻度アクセス、30日以上保存、低いストレージコスト、高いアクセスコスト
  # access_tier = "Hot"
  
  # enable_https_traffic_only: HTTPS通信のみを許可（セキュリティのため推奨）
  # enable_https_traffic_only = true
  
  # min_tls_version: 最小TLSバージョン（セキュリティ強化）
  # オプション: TLS1_0, TLS1_1, TLS1_2（推奨）
  # min_tls_version = "TLS1_2"
  
  # public_network_access_enabled: パブリックネットワークからのアクセスを許可
  # false にすると、プライベートエンドポイント経由のみアクセス可能
  # public_network_access_enabled = true
  
  # allow_nested_items_to_be_public: コンテナやBlobの公開アクセスを許可
  # セキュリティのため false を推奨（デフォルト: true）
  # allow_nested_items_to_be_public = false
  
  # blob_properties: Blobサービスの詳細設定（オプション）
  # blob_properties {
  #   # バージョニング
  #   versioning_enabled = true
  #   
  #   # 変更フィード（監査用）
  #   change_feed_enabled = true
  #   
  #   # 論理削除（soft delete）の設定
  #   delete_retention_policy {
  #     days = 7  # 削除されたBlobを保持する日数
  #   }
  #   
  #   container_delete_retention_policy {
  #     days = 7  # 削除されたコンテナを保持する日数
  #   }
  # }
  
  # network_rules: ネットワークアクセス制御（オプション）
  # network_rules {
  #   default_action             = "Deny"  # デフォルトでアクセス拒否
  #   ip_rules                   = ["123.456.789.0/24"]  # 許可するIPアドレス
  #   virtual_network_subnet_ids = [azurerm_subnet.example.id]  # 許可するサブネット
  #   bypass                     = ["AzureServices"]  # Azureサービスからのアクセスを許可
  # }
  
  # identity: マネージドIDの設定（他のAzureサービスとの連携用）
  # identity {
  #   type = "SystemAssigned"  # システム割り当てマネージドID
  # }
  
  # tags: リソースタグ
  # tags = {
  #   Environment = "Development"
  #   Project     = "StorageExample"
  # }
}