# Azure Functions プロジェクト

Azure Functions (Python v2 プログラミングモデル) をサーバーレス（Consumption Plan）で動かす独立した Terraform プロジェクト。

## 構成

- **リソースグループ** (`azurerm_resource_group`) — すべてのリソースを束ねるコンテナ
- **Storage Account** (`azurerm_storage_account`) — Function App のランタイム用（関数コード・ログ・状態管理）
- **App Service Plan** (`azurerm_service_plan`) — Linux Consumption（`Y1`）
- **Linux Function App** (`azurerm_linux_function_app`) — Python 3.11、`https_only = true`、Python v2 モデル有効化（`AzureWebJobsFeatureFlags=EnableWorkerIndexing`）
- **Application Insights** (`azurerm_application_insights`) — 監視・ログ分析（既存 Log Analytics ワークスペースに紐付け）

## ファイル

| ファイル | 役割 |
| --- | --- |
| [provider.tf](provider.tf) | `azurerm ~> 3.0` プロバイダー設定 |
| [variables.tf](variables.tf) | 名前・リージョン・Python バージョン・SKU 等の入力変数（バリデーション付き） |
| [resource_group.tf](resource_group.tf) | リソースグループ定義 |
| [storage_account.tf](storage_account.tf) | Function App ランタイム用 Storage Account |
| [service_plan.tf](service_plan.tf) | App Service Plan（Linux / Y1 Consumption） |
| [function_app.tf](function_app.tf) | Application Insights と Linux Function App の定義 |
| [outputs.tf](outputs.tf) | Function App URL、HTTP トリガーのエンドポイント、デプロイ／動作確認コマンドを出力 |
| [terraform.tfvars.example](terraform.tfvars.example) | `terraform.tfvars` のテンプレート |
| [python/](python/) | デプロイ対象の関数コード（`function_app.py` / `host.json` / `requirements.txt`） |

## 主な変数（デフォルト値）

- `location` = `Japan East`
- `resource_group_name` = `rg-azure-func-dev`
- `storage_account_name` = `stfuncdev001seiwan`（小文字英数字、3-24 文字、グローバル一意）
- `function_app_name` = `func-simple-dev-seiwan`（グローバル一意、URL の一部）
- `python_version` = `3.11`（`3.9` / `3.10` / `3.11` / `3.12` / `3.13` のみ許可）
- `service_plan_sku` = `Y1`（Consumption）

## 使い方

```powershell
terraform init
terraform plan
terraform apply
```

`terraform output function_app_url` で Function App の URL、`terraform output function_app_http_trigger_url` で HTTP トリガーのエンドポイントを確認できる。デプロイコマンドと動作確認コマンドは `deploy_command` / `test_command` 出力にまとまっている。

## 関数コードのデプロイ

Terraform はインフラのみを管理する。関数コード本体（[python/](python/)）は別途デプロイする：

```powershell
# Azure Functions Core Tools を使う場合
cd python
func azure functionapp publish $(terraform -chdir=.. output -raw function_app_name)
```

または Azure CLI による Zip デプロイは `terraform output deploy_command` に含まれている。

## 後片付け

```powershell
terraform destroy
```
