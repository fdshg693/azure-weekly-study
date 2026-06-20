# App Service プロジェクト（Azure OpenAI チャットボット）

Azure App Service（Linux / Node.js 20 LTS）上で動く Azure OpenAI チャットボットを Terraform で一発構築する独立プロジェクト。

公式チュートリアル [Build and deploy an Azure OpenAI (Express.js) chatbot - Azure App Service](https://learn.microsoft.com/en-us/azure/app-service/tutorial-ai-openai-chatbot-node) を Terraform 化したもの。**API キーを使わず、Web App のシステム割り当てマネージド ID から Azure OpenAI を呼び出す**のがポイント。

> ドキュメントの分担: 実行コマンドの順序は [QUICKSTART.md](QUICKSTART.md)、認証の概念とポータル手動設定は [ENTRA-AUTH.md](ENTRA-AUTH.md)、エラー対処・環境注意は [TROUBLESHOOTING.md](TROUBLESHOOTING.md)、アプリ実装は [app/README.md](app/README.md)。

## 構成

```
ユーザー ──HTTPS──> [Linux Web App (Express + EJS)]
                          │  ManagedIdentity / DefaultAzureCredential
                          ▼
                  [Azure OpenAI: gpt-4o-mini]
```

- **リソースグループ** (`azurerm_resource_group`)
- **App Service Plan** (`azurerm_service_plan`) — Linux / 既定 `B1`（F1 だと npm install でメモリ不足になることがある）
- **Linux Web App** (`azurerm_linux_web_app`) — Node.js 20 LTS、システム割り当てマネージド ID を有効化
- **Azure OpenAI アカウント** (`azurerm_cognitive_account`) — kind=`OpenAI`、`custom_subdomain_name` 付き（Entra ID 認証に必須）
- **モデルデプロイ** (`azurerm_cognitive_deployment`) — `gpt-4o-mini`
- **ロール割り当て** (`azurerm_role_assignment`) — Web App の MI に `Cognitive Services OpenAI User`

## ファイル

| ファイル | 役割 |
| --- | --- |
| [provider.tf](provider.tf) | `azurerm ~> 3.0` プロバイダー設定 |
| [variables.tf](variables.tf) | 名前・リージョン・SKU・OpenAI モデル設定など |
| [main.tf](main.tf) | RG / Plan / Web App / Azure OpenAI / モデルデプロイ / ロール割り当て |
| [outputs.tf](outputs.tf) | Web App URL、OpenAI エンドポイント、動作確認コマンド等 |
| [justfile](justfile) | Terraform 操作・パッケージ・デプロイ・ローカル開発のタスク |
| [app/](app/) | Express + EJS アプリ本体。**アプリ側の実装・認証デモの説明は [app/README.md](app/README.md) を参照** |
| [scripts/](scripts/) | Entra ID App Registration やテストユーザーの作成・確認・削除を行う PowerShell（一覧は [ENTRA-AUTH.md](ENTRA-AUTH.md#4-scripts-一覧)） |

## 主な変数（デフォルト値）

| 変数 | デフォルト | 説明 |
| --- | --- | --- |
| `location` | `Japan East` | App Service 系のリージョン |
| `openai_location` | `Japan East` | Azure OpenAI のリージョン。モデルの提供状況に応じて変更可 |
| `app_service_plan_sku` | `B1` | `F1` / `B1` / `S1` / `P1v2` / `P1v3` |
| `web_app_name` | `webapp-chatbot-dev-seiwan` | URL 　`https://<name>.azurewebsites.net` の一部、グローバル一意 |
| `openai_account_name` | `aoai-chatbot-dev-seiwan` | `custom_subdomain_name` にもなる、グローバル一意 |
| `openai_deployment_name` | `gpt-4o-mini` | デプロイ名（規約A: モデル名と一致。アプリは `app/config/models.js` で参照） |

## アプリ側の説明

`server.js` の Azure OpenAI 呼び出し（キーレス認証）の仕組み、`/profile` / `/profile-obo` の認証デモページ、ファイル構成などアプリ実装の詳細は **[app/README.md](app/README.md)** に分離した。
