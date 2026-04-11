# `terraform` フォルダ直下にある各プロジェクトの説明

## `app_service`

Azure App Service を使って最小限の Web サイトをデプロイするシンプルな構成。

### 作られるもの

- リソースグループ
- App Service Plan（Linux / Free F1 SKU）
- Linux Web App（Node.js 20 LTS ランタイム、HTTPS 強制）

### 使われている技術

- **Azure**: Azure App Service (Web Apps), App Service Plan
- **Terraform**: azurerm プロバイダー (~> 3.0)、変数バリデーション、HTTPS リダイレクト設定
- **ランタイム**: Node.js 20 LTS（Linux）


## `azure_func`

Azure Functions (Python) をサーバーレスで動かすための構成。

### 作られるもの

- リソースグループ
- ストレージアカウント（Function App のランタイム用）
- App Service Plan（Linux Consumption Plan / Y1 SKU）
- Linux Function App（Python v2 プログラミングモデル）
- Application Insights（監視・ログ）

### 使われている技術

- **Azure**: Azure Functions, Azure Storage, Application Insights
- **Terraform**: azurerm プロバイダー (~> 3.0)、変数バリデーション、Output のセンシティブ対応
- **言語/ランタイム**: Python 3.11

---

## `key_vault`

Azure Key Vault を作成し、RBAC でアクセス制御を行い、サンプルシークレットを格納するシンプルな構成。

### 作られるもの

- リソースグループ
- Key Vault（Standard SKU、RBAC 認証、ソフトデリート有効）
- RBAC ロール割り当て（現在のユーザーに Key Vault Secrets Officer）
- サンプルシークレット（動作確認用）

### 使われている技術

- **Azure**: Azure Key Vault, Azure RBAC
- **Terraform**: azurerm プロバイダー (~> 3.0)、データソース (`azurerm_client_config`)、RBAC ロール割り当て、`depends_on` による依存関係制御、変数バリデーション、センシティブ変数
- **セキュリティ**: RBAC ベースのアクセス制御、ソフトデリート、シークレット値の機密保護

---

## `storage_accounts_private_endpoint`

ストレージアカウントへのアクセスをプライベートエンドポイント経由に限定し、VNet 内の VM から安全に接続する構成。

### 作られるもの

- リソースグループ
- ストレージアカウント（Blob バージョニング、ソフトデリート有効）
- VNet（10.0.0.0/16）とサブネット 2 つ（プライベートエンドポイント用 / VM 用）
- NSG（SSH ルール付き）
- プライベート DNS ゾーン（`privatelink.blob.core.windows.net`）と VNet リンク
- プライベートエンドポイント（Blob サービス向け）
- ストレージコンテナーおよびサンプル Blob
- パブリック IP、NIC、Linux VM（Ubuntu 22.04 LTS / 検証用）

### 使われている技術

- **Azure**: Azure Storage, VNet, NSG, Private DNS Zone, Private Endpoint, Virtual Machines, Public IP
- **Terraform**: azurerm プロバイダー (~> 3.0)、変数の正規表現バリデーション、base64 エンコード（cloud-init）、センシティブ Output
- **セキュリティ**: HTTPS 強制、TLS 1.2、共有キー管理、パブリックアクセス無効化

---

## `storage_accounts_simple`

ストレージアカウントにファイルをアップロードし、SAS トークンで読み取りアクセスを提供するシンプルな構成。

### 作られるもの

- リソースグループ
- ストレージアカウント（GRS レプリケーション）
- ストレージコンテナー
- Block Blob（ローカルファイルのアップロード）
- SAS トークン（読み取り専用、24 時間有効）

### 使われている技術

- **Azure**: Azure Storage (Blob)
- **Terraform**: azurerm プロバイダー (~> 3.0)、データソース (`azurerm_storage_account_sas`)、`filemd5()` によるファイル変更検知、`timestamp()` / `timeadd()` による有効期限計算、変数バリデーション

---

