# Development Notes

このファイルはローカル実行、コード配布の仕組み、開発時の注意点をまとめたメモです。

## ローカル実行

`justfile` を使う場合:

```powershell
just local-install
just local-start
```

手動で実行する場合:

`python` ディレクトリで依存関係をインストールして起動します。

```powershell
cd python
pip install -r requirements.txt
func start
```

ローカル実行時のベース URL:

```text
http://localhost:7071/api
```

## コード配布の仕組み

`main.bicep` は以下のファイルを読み込みます。

- `python/function_app.py`
- `python/host.json`
- `python/requirements.txt`

その内容を `modules/function-code-deployment.bicep` から Deployment Script に渡し、zip deploy を実行します。これにより、インフラ作成と最小限のアプリ配布を 1 回のデプロイで完了できます。

## セキュリティモデル（Managed Identity + Key Vault）

このサンプルでは以下のレイヤで鍵を排除しています。

### 1. Function App → Storage（identity-based connection）

`AzureWebJobsStorage` は接続文字列ではなく以下の App Setting で構成します。

- `AzureWebJobsStorage__accountName`
- `AzureWebJobsStorage__credential = managedidentity`
- `AzureWebJobsStorage__blobServiceUri` / `queueServiceUri` / `tableServiceUri`

Function App の System-Assigned Managed Identity に対し、Storage Account スコープで以下のロールを付与します（`modules/role-assignments.bicep`）。

- Storage Blob Data Owner
- Storage Queue Data Contributor
- Storage Table Data Contributor
- Storage File Data SMB Share Contributor（Premium プランの content share アクセス用）

**重要**: identity-based `AzureWebJobsStorage` は Premium (EP*) 以上が必須です。Y1 Consumption では未対応のため、`servicePlanSku` は `EP1` を既定にしています。

### 2. APIM → Azure OpenAI（authentication-managed-identity ポリシー）

APIM の System-Assigned Managed Identity を有効化し、AOAI スコープで `Cognitive Services OpenAI User` ロールを付与します。`apim-aoai-api.bicep` の policy は次のように MI から Entra トークンを取得して `Authorization: Bearer` を付けます。

```xml
<inbound>
  <base />
  <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
</inbound>
```

AOAI 側は `disableLocalAuth: true` で key 認証ルートを物理的に閉じています。`api-key` ヘッダーは無視され 401 になるため、key が漏れても被害は出ません。

### 3. APIM ⇔ Function App の共有シークレット（Key Vault 経由）

`BACKEND_SHARED_SECRET` は Key Vault に `backend-shared-secret` シークレットとして格納されます。

- **Function App**: App Setting に `@Microsoft.KeyVault(SecretUri=https://<vault>.vault.azure.net/secrets/backend-shared-secret)` を設定し、System-Assigned MI で取得（`keyVaultReferenceIdentity: 'SystemAssigned'`）。
- **APIM**: Named value を `keyVault.secretIdentifier` 付きで作成し、System-Assigned MI で取得。policy は `{{function-backend-secret}}` で参照。
- どちらも **versionless URI** を使うため、Key Vault でシークレットをローテートすれば双方が自動追従します。

Function App は受け取った `x-backend-auth` ヘッダー値を `BACKEND_SHARED_SECRET` と突き合わせ、合わない場合は `401 Unauthorized` を返します。

### 4. RBAC ロール一覧（`modules/role-assignments.bicep`）

| principal       | scope             | role                                       |
| --------------- | ----------------- | ------------------------------------------ |
| Function App MI | Storage Account   | Storage Blob Data Owner                    |
| Function App MI | Storage Account   | Storage Queue Data Contributor             |
| Function App MI | Storage Account   | Storage Table Data Contributor             |
| Function App MI | Storage Account   | Storage File Data SMB Share Contributor    |
| Function App MI | Key Vault         | Key Vault Secrets User                     |
| APIM MI         | Key Vault         | Key Vault Secrets User                     |
| APIM MI         | Azure OpenAI      | Cognitive Services OpenAI User （AOAI 有効時のみ） |

冪等な role assignment 名は `guid(scope, principal, role)` で生成するのが Bicep の標準パターンです。

## `backendSharedSecret` の渡し方

`main.bicep` の `backendSharedSecret` パラメータは secure です。

- **既定**: 未指定の場合 `newGuid()` で生成。再デプロイのたびに変わるため、`test.local.http` に貼っていた古い値は無効になります。
- **固定値**: `main.local.bicepparam` で `param backendSharedSecret = '...'` を指定。ただし bicepparam を Git に含めないでください。
- **推奨**: `az.getSecret()` を使って別の Key Vault（ブートストラップ用）から取り出す方式。値が bicepparam にもデプロイ履歴にも残りません。詳細は `main.local.bicepparam.example` のコメント参照。

現在の値を確認したい場合は `just backend-secret` か、`az keyvault secret show` で直接 Key Vault を参照してください。

## APIM と Azure OpenAI の接続

Azure OpenAI を APIM 配下へ追加する場合は、Bicep が Azure OpenAI リソース本体とモデルデプロイを作成し、Managed Identity 認証で APIM の別 API として公開します。

- `enableAzureOpenAiApi = true`
- `azureOpenAiLocation = '<aoai-region>'`
- `azureOpenAiDeploymentName = '<deployment-name>'`
- `azureOpenAiModelName = '<model-name>'`
- `azureOpenAiModelVersion = '<optional-version>'`

APIM 側では AOAI 用の別 Product / Subscription を作ります。公開パスは `/aoai` です。利用者は引き続き `X-API-Key`（APIM サブスクリプションキー）を送ります。APIM から AOAI への内部呼び出しは Managed Identity による Entra トークン認証です。

モデルの利用可否はリージョンと SKU に依存します。`enableAzureOpenAiApi = true` にする場合は、対象リージョンでそのモデルがデプロイ可能かを確認してください。たとえば `japaneast` で `gpt-4o-mini` を使う場合、regional `Standard` はサポートされず `GlobalStandard` が必要です。

## MCP Server 向けの APIM operation 定義

APIM の組み込み機能で REST API を MCP Server としてエクスポートする場合、APIM に登録された operation の名前、説明、パラメータ、リクエスト例が MCP ツールの見え方に影響します。

このサンプルでは `modules/apim-crud-api.bicep` に以下を明示的に入れています。

- `POST /items` と `PUT /items/{id}` の JSON リクエスト例
- `GET` / `PUT` / `DELETE` の `id` パラメータ説明
- 各操作のレスポンス説明と代表例

MCP エージェントから使いやすいツールにしたい場合は、Function 実装だけでなく APIM operation 定義もあわせて更新してください。手順自体は `MCP.md` にまとめています。

## Git に入れないもの

以下は Git 管理対象外です。

- `main.json`
- `*.local.bicepparam`
- `*.local.http`
- `_scratch*.json`

共通値は `main.bicepparam` に置き、個人用・環境用の値は `main.local.bicepparam` に分離してください。

## 注意事項

- データは `function_app.py` 内のインメモリ辞書に保持しているだけなので永続化されません
- Function App の再起動やスケール時にデータは消えます
- 利用者向け認証は APIM のサブスクリプションキーです
- 共有シークレットは Key Vault 管理ですが、本番用途では追加で Private Endpoint、Purge Protection、ネットワーク制限、監査ログ収集などを検討してください
- App Service Plan は EP1 を既定にしているためアイドル時もコストが発生します（学習が終わったらリソースグループごと削除を推奨）
- `main.json` は Bicep から生成される ARM テンプレートです

## 関連ファイル

- `main.bicep`
- `main.bicepparam`
- `main.local.bicepparam.example`
- `python/function_app.py`
- `test.http`
