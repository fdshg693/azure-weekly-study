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

## `func_keyvault_split`

Azure Functions の **権限分離** を学ぶための構成。「最小権限の Reader」と「シークレット更新が可能な Writer」を 2 つの独立した Function App に分け、共通の Key Vault シークレットを参照／更新する。同一 Function App 内の関数は Managed Identity を共有するため関数単位での RBAC スコープ分離ができない、という制約を体感する目的の学習用プロジェクト。

### 作られるもの

- リソースグループ
- Key Vault（Standard / RBAC 認証）+ 初期シークレット `greeting-name`
- Storage Account × 2（Reader / Writer 専用ランタイムストレージ）
- App Service Plan（Linux Consumption Y1、Reader/Writer で共有）
- Log Analytics Workspace + Application Insights（Workspace-based モード、Reader/Writer で共有）
- Reader Function App（System-Assigned MI、`Key Vault Secrets User` 付与、匿名 `GET /api/message`、Key Vault reference で app setting 注入）
- Writer Function App（System-Assigned MI、`Key Vault Secrets Officer` 付与、Function キー保護 `POST /api/secret`、SDK 経由で更新）
- 現在のユーザーへの `Key Vault Secrets Officer`（初期シークレット作成 + CLI 動作確認用）

### 使われている技術

- **Azure**: Azure Functions (Python v2), Azure Key Vault, Azure RBAC, Managed Identity, Application Insights, Key Vault references (`@Microsoft.KeyVault(SecretUri=...)`)
- **Terraform**: azurerm プロバイダー (~> 3.0)、`provider.features.key_vault.purge_soft_delete_on_destroy`、`identity { type = "SystemAssigned" }`、`azurerm_role_assignment` で MI へのスコープ別 RBAC、`azurerm_key_vault_secret` の `versionless_id` 参照、`lifecycle.ignore_changes = [value]` で Writer による値更新を許容
- **Functions 認証**: `auth_level=ANONYMOUS`（Reader）と `auth_level=FUNCTION`（Writer / Function キー保護）の対比
- **言語/ライブラリ**: Python 3.11、`azure-functions`、`azure-identity`、`azure-keyvault-secrets`

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

