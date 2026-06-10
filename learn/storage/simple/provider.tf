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
      # 形式: <namespace>/<provider-name>
      source  = "hashicorp/azurerm"
      
      # version: 使用するプロバイダーのバージョン制約
      # ~> 3.0 は「3.x系の最新版を使用（4.0未満）」を意味
      # バージョン指定の例:
      #   "= 3.0.0"  : 完全一致（3.0.0のみ）
      #   ">= 3.0.0" : 3.0.0以上
      #   "~> 3.0"   : 3.0以上、4.0未満（マイナーバージョンアップデート許可）
      #   "~> 3.0.0" : 3.0.0以上、3.1.0未満（パッチバージョンのみ許可）
      version = "~> 3.0"
    }
  }
  
  # required_version: Terraform本体のバージョン制約（オプション）
  # 例: required_version = ">= 1.0.0"
}

# ============================================================================
# Azureプロバイダーの設定
# ============================================================================
# プロバイダーブロックは、特定のクラウドプロバイダーへの接続を設定

provider "azurerm" {
  # features: azurermプロバイダーで必須のブロック
  # 各種機能の動作をカスタマイズできます
  features {
    # 例: リソースグループを削除する際の動作を制御
    # resource_group {
    #   prevent_deletion_if_contains_resources = true  # リソースが含まれる場合は削除を防止
    # }
    
    # 例: Key Vaultの削除動作を制御
    # key_vault {
    #   purge_soft_delete_on_destroy = true  # 削除時にソフトデリートをパージ
    #   recover_soft_deleted_key_vaults = true  # 削除されたKey Vaultを復元
    # }
    
    # 例: 仮想マシンの動作を制御
    # virtual_machine {
    #   delete_os_disk_on_deletion = true  # VM削除時にOSディスクも削除
    # }
  }
  
  # 認証方法のオプション（環境変数やAzure CLIで認証する場合は不要）:
  # subscription_id = "00000000-0000-0000-0000-000000000000"
  # client_id       = "00000000-0000-0000-0000-000000000000"
  # client_secret   = var.client_secret
  # tenant_id       = "00000000-0000-0000-0000-000000000000"
  
  # その他のオプション:
  # skip_provider_registration = false  # プロバイダーの自動登録をスキップ
  # storage_use_azuread = false  # ストレージ認証にAzure ADを使用
}