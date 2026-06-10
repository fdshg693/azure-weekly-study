# ============================================================================
# Terraformの設定ブロック
# ============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# ============================================================================
# Azureプロバイダーの設定
# ============================================================================

provider "azurerm" {
  features {
    resource_group {
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
