# ============================================================================
# Terraform / プロバイダー設定
# ============================================================================
# 兄弟プロジェクト（projects/chatbot）と揃えて azurerm 3.x を使う。

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
  }

  # 認証は Azure CLI（az login）または環境変数（ARM_*）を使用する。
}
