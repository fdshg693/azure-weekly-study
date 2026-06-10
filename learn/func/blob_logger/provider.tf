# ============================================================================
# Terraform / プロバイダー設定
# ============================================================================
# このプロジェクトは「Storage Account + Blob トリガーの Function App」を
# 1 つの apply で構築する独立 Terraform プロジェクト。
#
# 学習テーマ:
#   Storage の特定コンテナ（uploads）にファイルがアップロードされるたびに
#   Function が起動し、別コンテナ（logs）にログファイルを書き出す。

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # 中にリソースが残っていても destroy できるようにする（学習用途）
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
