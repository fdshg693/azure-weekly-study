# Azure Functions CRUD Sample with Bicep

`bicep/apim_learn` は、Python 製のシンプルな CRUD API を Azure Functions (Linux) にデプロイするためのサンプルです。Bicep で Azure リソースを作成し、API Management を前段に置いて API キー認証付きで公開します。必要に応じて、Azure OpenAI リソースとモデルデプロイも同じ Bicep で作成し、APIM 配下の別 API として追加できます。

学習用途として、**鍵 (API key / connection string) に頼らない Azure 標準のセキュリティモデル**を採用しています。

- Function App → Storage は **Managed Identity + RBAC**（identity-based `AzureWebJobsStorage`）
- APIM → Azure OpenAI は **APIM の Managed Identity + `authentication-managed-identity` ポリシー**（AOAI は `disableLocalAuth: true` で key 認証遮断）
- APIM と Function App の共有シークレットは **Key Vault に格納**し、双方が Managed Identity で取得

この README は最初に全体像をつかむための入口です。デプロイ手順、API キー取得、ローカル開発時の注意は別ファイルへ分割しています。

## このサンプルで作るもの

- Storage Account
- App Service Plan（Premium / EP1。Identity-based Storage 接続のため Y1 Consumption は非対応）
- Linux Function App（System-Assigned Managed Identity）
- Key Vault（RBAC 認可モード）+ `backend-shared-secret`
- API Management（System-Assigned Managed Identity）
- APIM Product / Subscription
- APIM の CRUD API（OpenAPI / MCP export を意識した詳細な operation 定義）
- Azure OpenAI リソースとモデルデプロイ（任意 / `disableLocalAuth: true`）
- Azure OpenAI への APIM プロキシ API（任意 / MI 認証）
- RBAC ロール割り当て一式（Storage / Key Vault / Azure OpenAI）
- Function コード配布用 Deployment Script

`publishFunctionCode = true` の場合、Bicep デプロイ時に Python コードも Function App へ発行されます。

## API 概要

このサンプルは APIM 経由で API キー認証を行う HTTP API を提供します。

- `GET /items`: 全件取得
- `GET /items/{id}`: 1 件取得
- `POST /items`: 新規作成
- `PUT /items/{id}`: 更新
- `DELETE /items/{id}`: 削除

Azure OpenAI を有効化した場合は、別 API として以下のような公開 URL も追加されます。

- `POST /aoai/deployments/{deploymentId}/chat/completions`
- `POST /aoai/deployments/{deploymentId}/embeddings`

公開 URL は Azure Functions 直下ではなく APIM 側です。Function App 直下の URL はバックエンド用途で、通常の利用者は使いません。

## セキュリティモデル

```
┌────────────────┐  X-API-Key   ┌──────────────────┐  Bearer (MI)  ┌─────────────────┐
│ クライアント    │ ───────────▶ │ API Management   │ ───────────▶  │ Azure OpenAI    │
│                │              │ (SystemAssigned  │              │ disableLocalAuth│
└────────────────┘              │  Managed         │              └─────────────────┘
                                │  Identity)       │
                                │                  │  x-backend-auth (KV ref)
                                │                  │ ───────────▶
                                │                  │              ┌─────────────────┐
                                └──────────┬───────┘              │ Function App    │
                                           │                      │ (SystemAssigned │
                                           │ KV reference         │  Managed        │
                                           ▼                      │  Identity)      │
                                ┌──────────────────┐              └─────┬───────────┘
                                │ Key Vault        │ ◀──────── MI ──────┘
                                │ (RBAC auth)      │                    │
                                │ backend-shared-  │              ┌─────▼───────────┐
                                │ secret           │              │ Storage Account │
                                └──────────────────┘              │ (Blob/Queue/    │
                                                                  │  Table/File)    │
                                                                  └─────────────────┘
```

- **クライアント → APIM**: APIM のサブスクリプションキー (`X-API-Key`)
- **APIM → Function App**: Key Vault 経由で取得した共有シークレットを `x-backend-auth` に付与
- **APIM → Azure OpenAI**: System-Assigned MI から Entra トークンを取得、`Authorization: Bearer` で呼び出し
- **Function App → Storage**: System-Assigned MI（identity-based `AzureWebJobsStorage`）
- **Function App → Key Vault**: System-Assigned MI（App Setting の `@Microsoft.KeyVault(...)` 参照）

## ファイル構成

- `justfile`: よく使う Azure CLI / Functions Core Tools コマンドの入口
- `main.bicep`: モジュールを呼び出すオーケストレーター
- `modules/core.bicep`: Storage Account と App Service Plan
- `modules/key-vault.bicep`: Key Vault（RBAC 認可モード） + 共有シークレット
- `modules/function-app.bicep`: Linux Function App（MI、Key Vault reference）
- `modules/apim.bicep`: API Management（MI）、Product、Subscription、Policy
- `modules/apim-crud-api.bicep`: CRUD API の operation 定義と policy
- `modules/apim-aoai-api.bicep`: Azure OpenAI 用 API の operation 定義と MI 認証 policy
- `modules/azure-openai.bicep`: Azure OpenAI アカウントとモデルデプロイ（`disableLocalAuth: true`）
- `modules/role-assignments.bicep`: Function App / APIM の MI に対する RBAC 割り当て一式
- `modules/function-code-deployment.bicep`: zip deploy 用 Deployment Script
- `main.bicepparam`: Git に含める共通デフォルト値
- `main.local.bicepparam.example`: ローカル専用上書きパラメータの雛形（`az.getSecret()` 例も含む）
- `python/function_app.py`: CRUD API 実装
- `test.http`: API 確認用の REST Client リクエスト集

Azure OpenAI を APIM に追加する場合は、`main.local.bicepparam` などで `enableAzureOpenAiApi = true` を指定します。必要に応じて `azureOpenAiLocation`、`azureOpenAiDeploymentName`、`azureOpenAiModelName`、`azureOpenAiModelVersion`、`azureOpenAiDeploymentSkuName`、`azureOpenAiDeploymentCapacity` を上書きしてください。`japaneast` で `gpt-4o-mini` を使う場合は、`azureOpenAiDeploymentSkuName = 'GlobalStandard'` が必要です。

## 最短手順

1. リソースグループを作成する
2. 必要なら `main.local.bicepparam` を作る
3. `just deploy` または `just deploy-local` でデプロイする
4. `just api-key` で APIM の API キーを取得する
5. `test.http` または PowerShell で疎通確認する

最初に使うコマンドだけ書くと以下です。

```powershell
just group-create
just init-local-param
just deploy
just outputs
just api-key
```

詳細は以下を参照してください。

- [DEPLOYMENT.md](./DEPLOYMENT.md): デプロイ手順、出力値、API キー取得、動作確認
- [DEVELOPMENT.md](./DEVELOPMENT.md): ローカル実行、コード配布、セキュリティモデル、Git 管理ルール

## コストに関する注意

App Service Plan の既定 SKU は **EP1 (Premium)** で、アイドル時も時間課金が発生します（東京リージョンで概ね ¥150〜200/日）。学習が終わったらリソースグループごと削除することを推奨します。

Y1 (Consumption) は安価ですが identity-based `AzureWebJobsStorage` に対応していないため、本テンプレートのセキュリティモデルでは利用できません。

## 前提条件

- Azure サブスクリプション
- Azure CLI
- Bicep CLI または Azure CLI の Bicep サポート
- Azure にログイン済みであること
- サブスクリプション内で **Microsoft.Authorization/roleAssignments を作成できる権限**（User Access Administrator または Owner）
- Just
- Azure OpenAI リソース作成とモデルデプロイの権限（AOAI を有効化する場合）

ローカル実行や手動発行も行う場合は以下も必要です。

- Python 3.11 以上
- Azure Functions Core Tools
- VS Code REST Client 拡張機能

## 参考

- [DEPLOYMENT.md](./DEPLOYMENT.md)
- [DEVELOPMENT.md](./DEVELOPMENT.md)
- `python/function_app.py`
- `test.http`
