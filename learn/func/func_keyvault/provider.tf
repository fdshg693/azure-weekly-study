# ============================================================================
# Terraform / プロバイダー設定
# ============================================================================
# このプロジェクトは「Key Vault + 2 つの Function App（Reader / Writer）」を
# 1 つの apply で構築する独立 Terraform プロジェクト。

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
      prevent_deletion_if_contains_resources = false
    }

    # ソフトデリート期間中に同名 Key Vault を再作成できるよう、
    # destroy 時に purge（完全削除）してしまう設定。
    # 本番環境では false（=ソフトデリートのみ）にすること。
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }

  # 認証情報は環境変数または Azure CLI の認証を使用することを推奨
  # 環境変数:
  #   - ARM_SUBSCRIPTION_ID
  #   - ARM_TENANT_ID
  #   - ARM_CLIENT_ID
  #   - ARM_CLIENT_SECRET
}
