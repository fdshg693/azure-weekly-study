# ============================================================================
# Storage Accountの定義
# ============================================================================
# プライベートエンドポイント経由でアクセスするStorage Account

resource "azurerm_storage_account" "main" {
  name                = var.storage_account_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # パフォーマンスと冗長性の設定
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type

  # account_kind: ストレージアカウントの種類
  # StorageV2: 汎用v2、最新機能をサポート（推奨）
  account_kind = "StorageV2"

  # access_tier: Blobデータのアクセス頻度に基づく階層
  # Hot: 頻繁にアクセスされるデータ向け
  # Cool: 低頻度アクセスデータ向け（30日以上保存推奨）
  access_tier = "Hot"

  # ============================================================================
  # セキュリティ設定（プライベートエンドポイント使用時の重要な設定）
  # ============================================================================

  # https_traffic_only_enabled: HTTPS通信のみを許可（推奨: true）
  # セキュリティのため、常にtrueにすることを推奨
  https_traffic_only_enabled = true

  # min_tls_version: 最小TLSバージョン（セキュリティ強化）
  # TLS1_2: 現在推奨される最小バージョン
  # TLS1_3: 利用可能な場合は最も安全
  min_tls_version = "TLS1_2"

  # public_network_access_enabled: パブリックネットワークからのアクセス制御
  # false: プライベートエンドポイント経由のみアクセス可能（最も安全）
  # true: パブリックエンドポイントも有効（network_rulesで制御可能）
  # プライベートエンドポイント専用にする場合は false を推奨
  # 注意: Terraformでコンテナ/Blobを作成する場合、trueにしてnetwork_rulesで制限する必要があります
  public_network_access_enabled = true

  # allow_nested_items_to_be_public: コンテナやBlobの公開アクセス許可
  # false: すべてのコンテナとBlobは認証が必要（推奨）
  # true: 個別のコンテナで公開アクセスを許可可能
  allow_nested_items_to_be_public = false

  # shared_access_key_enabled: Shared Access Key（アカウントキー）の使用を許可
  # false: Azure AD認証のみを強制（最もセキュア）
  # true: アカウントキーによるアクセスも許可（デフォルト）
  shared_access_key_enabled = true

  # ============================================================================
  # Blob サービスの詳細設定
  # ============================================================================
  blob_properties {
    # バージョニング有効化: Blobの以前のバージョンを自動的に保持
    versioning_enabled = true

    # 変更フィード有効化: すべての変更をログとして記録（監査用）
    change_feed_enabled = true

    # 最後のアクセス時刻追跡: アクセスパターンの分析やライフサイクル管理に使用
    last_access_time_enabled = true

    # 論理削除（Soft Delete）の設定: 削除されたBlobを指定期間保持
    delete_retention_policy {
      days = 7  # 1-365日の範囲で設定可能
    }

    # コンテナの論理削除設定
    container_delete_retention_policy {
      days = 7
    }

    # CORS (Cross-Origin Resource Sharing) ルール（Webアプリケーションからのアクセス用）
    # cors_rule {
    #   allowed_headers    = ["*"]
    #   allowed_methods    = ["GET", "HEAD", "POST", "PUT"]
    #   allowed_origins    = ["https://example.com"]
    #   exposed_headers    = ["*"]
    #   max_age_in_seconds = 3600
    # }
  }

  # ============================================================================
  # ネットワークルール（public_network_access_enabled = true の場合のみ有効）
  # ============================================================================
  network_rules {
    # default_action: デフォルトのアクセス動作
    # Deny: 明示的に許可されたもの以外拒否（ホワイトリスト方式）
    # Allow: すべて許可（非推奨）
    default_action = "Allow"  # 開発環境用。本番環境では"Deny"にしてip_rulesで制限

    # 本番環境では以下を使用:
    # default_action = "Deny"
    # ip_rules = ["あなたのパブリックIP"]  # Terraform実行環境のIPアドレス

    # virtual_network_subnet_ids: 許可するVNetサブネットID
    # virtual_network_subnet_ids = [azurerm_subnet.vm.id]

    # bypass: ネットワークルールをバイパスできるAzureサービス
    # オプション: AzureServices, Logging, Metrics, None
    bypass = ["AzureServices", "Logging", "Metrics"]
  }

  # ============================================================================
  # マネージドIDの設定（他のAzureサービスとの認証統合用）
  # ============================================================================
  # identity {
  #   type = "SystemAssigned"  # システム割り当てマネージドID
  #   # または
  #   # type         = "UserAssigned"
  #   # identity_ids = [azurerm_user_assigned_identity.example.id]
  # }

  tags = var.tags

  # 注意: public_network_access_enabled = false に設定した場合、
  # Terraformの実行環境もプライベートエンドポイント経由でアクセスできる必要があります
  # そうでない場合、Blob のアップロードなどが失敗する可能性があります
}
