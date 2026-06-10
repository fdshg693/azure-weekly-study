# ============================================================================
# Terraformの設定ブロック
# ============================================================================
# このブロックでは、Terraformの動作や必要なプロバイダーを定義します

terraform {
  # required_providers: 使用するプロバイダーとそのバージョンを指定
  # プロバイダーは、各クラウドサービス（Azure、AWS、GCPなど）とのAPIを管理
  required_providers {
    azurerm = {
      # source: プロバイダーの取得元（Terraform Registry）
      source = "hashicorp/azurerm"

      # version: ~> 3.0 は「3.x系の最新版を使用（4.0未満）」を意味
      version = "~> 3.0"
    }
  }
}

# ============================================================================
# Azureプロバイダーの設定
# ============================================================================
# プロバイダーブロックは、特定のクラウドプロバイダーへの接続を設定

provider "azurerm" {
  # features: azurermプロバイダーで必須のブロック
  features {
    # resource_group: リソースグループ関連の動作設定
    resource_group {
      # prevent_deletion_if_contains_resources: リソースが含まれる場合は削除を防止
      prevent_deletion_if_contains_resources = false
    }
  }

  # 認証情報は環境変数または Azure CLI の認証を使用することを推奨
  # 環境変数:
  #   - ARM_SUBSCRIPTION_ID
  #   - ARM_TENANT_ID
  #   - ARM_CLIENT_ID
  #   - ARM_CLIENT_SECRET
}
