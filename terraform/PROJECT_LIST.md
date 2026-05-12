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

Azure Static Web Apps + HTMX で同期版の乱数 API を叩く構成に加え、**Logic Apps（入口）→ Service Bus（キュー）→ Worker Function（ワーカー）→ Table Storage** の非同期パイプラインを Logic App の `Until` ループで疑似同期 RPC にラップしたデモ構成も含む。

### 作られるもの

- リソースグループ
- ストレージアカウント（Function App ランタイム + Table `results`）
- App Service Plan（Linux Consumption Plan / Y1 SKU）
- Linux Function App（Python v2）
  - `/api/random` — 同期版（既存）
  - `worker` — Service Bus キュー `jobs` のトリガー（スリープ → 乱数 → Table 書き込み）
  - `/api/status` — Logic App の Until がポーリングする結果取得 API
- Application Insights（監視・ログ）
- Service Bus Namespace（Basic）+ Queue `jobs` + 認可ルール
- Logic App (Consumption) — HTTP トリガー → Compose → ServiceBus 送信 → Until → Response
- ServiceBus 用 API Connection
- Static Web Apps（Free SKU、HTMX ページを配信）

### 使われている技術

- **Azure**: Azure Functions, Azure Static Web Apps, Azure Storage（Blob+Table）, Application Insights, **Azure Service Bus**, **Azure Logic Apps (Consumption)**
- **Terraform**: azurerm プロバイダー (~> 3.0)、`azurerm_logic_app_workflow` + `azurerm_logic_app_action_custom`（Compose / ApiConnection / Until / Response）、`azurerm_api_connection`、`azurerm_servicebus_namespace_authorization_rule`、Output のセンシティブ対応
- **Functions バインディング**: `service_bus_queue_trigger`、`table_output`、`table_input`（`{Query.jobId}` 動的バインド）
- **言語/ランタイム**: Python 3.11、HTMX 2.x（CDN）
- **ツール**: just、Azure Functions Core Tools、SWA CLI

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

ストレージアカウントの静的Webサイトホスティング機能で `index.html` / `error.html` だけを匿名公開し、その他のファイルは private コンテナ + SAS トークン経由でしかアクセスできないようにした構成。

### 作られるもの

- リソースグループ
- ストレージアカウント（GRS レプリケーション、`static_website` 有効、`allow_nested_items_to_be_public = false`）
- `$web` コンテナ内の `index.html` / `error.html`（静的Webサイトとして匿名公開）
- private コンテナと private Blob（匿名アクセス不可）
- SAS トークン（private Blob 用、読み取り専用、24 時間有効）

### 使われている技術

- **Azure**: Azure Storage (Blob, 静的Webサイトホスティング)
- **Terraform**: azurerm プロバイダー (~> 3.0)、`static_website` ブロック、データソース (`azurerm_storage_account_sas`)、`filemd5()` によるファイル変更検知、`timestamp()` / `timeadd()` による有効期限計算、変数バリデーション
- **セキュリティ**: ストレージアカウントレベルでの匿名公開禁止、Web エンドポイント経由は `$web` コンテナの中身のみに限定

---

