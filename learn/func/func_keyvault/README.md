# Func + Key Vault（権限分割）プロジェクト

Azure Functions の **「最小権限の Reader」** と **「シークレット更新が可能な Writer」** を
2 つの独立した Function App として作成し、Key Vault シークレットを共有する構成。

「Managed Identity × Key Vault × RBAC スコープ × Functions の auth level」を
まとめて学べる学習用プロジェクト。

## なぜ Function App を 2 つに分けるのか

同じ Function App 内の関数は **同じ Managed Identity を共有する** ため、
関数単位で RBAC スコープを変えることはできない。

「読み取り専用な関数」と「更新可能な関数」を本当に **権限レベルで** 分離するなら、
Function App ごと分けるしかない。このプロジェクトはそれを Terraform で実現する。

| 関数 | Function App | Managed Identity の RBAC | 認証 | アクセス方法 |
| --- | --- | --- | --- | --- |
| `GET /api/message` | Reader | Key Vault Secrets **User**（read のみ） | 匿名 | Key Vault reference 経由で app setting に注入 |
| `POST /api/secret` | Writer | Key Vault Secrets **Officer**（read/write/delete） | Function キー | SDK (`azure-keyvault-secrets`) で更新 |

## 作られるもの

- リソースグループ（`rg-func-kv-split-dev`）
- Key Vault（RBAC モード、Standard SKU）+ 初期シークレット `greeting-name`
- Storage Account × 2（Reader / Writer 専用）
- App Service Plan × 1（Linux Consumption Y1、両 Function App で共有）
- Log Analytics Workspace + Application Insights（Workspace-based モード、両 Function App で共有）
- Reader Function App + System-Assigned MI + RBAC `Key Vault Secrets User`
- Writer Function App + System-Assigned MI + RBAC `Key Vault Secrets Officer`
- 現在のユーザーへの RBAC `Key Vault Secrets Officer`（初期シークレット作成 / CLI 動作確認用）

## ファイル

| ファイル | 役割 |
| --- | --- |
| [provider.tf](provider.tf) | `azurerm ~> 3.0` プロバイダー設定（Key Vault は destroy 時に purge） |
| [variables.tf](variables.tf) | リソース名（グローバル一意）・Python バージョン・シークレット名等 |
| [resource_group.tf](resource_group.tf) | リソースグループ + `azurerm_client_config` |
| [key_vault.tf](key_vault.tf) | Key Vault + 現在のユーザー RBAC + 初期シークレット（`ignore_changes = [value]`） |
| [storage_accounts.tf](storage_accounts.tf) | Reader / Writer 専用 Storage Account |
| [service_plan.tf](service_plan.tf) | 共有 Consumption Plan |
| [application_insights.tf](application_insights.tf) | 共有 Log Analytics Workspace + Application Insights（Workspace-based） |
| [function_app_reader.tf](function_app_reader.tf) | Reader Function App + MI + Secrets User RBAC + Key Vault reference 注入 |
| [function_app_writer.tf](function_app_writer.tf) | Writer Function App + MI + Secrets Officer RBAC |
| [outputs.tf](outputs.tf) | URL や動作確認コマンドを出力 |
| [python/reader/function_app.py](python/reader/function_app.py) | Reader の Python v2 関数コード（Key Vault SDK を import しない） |
| [python/writer/function_app.py](python/writer/function_app.py) | Writer の Python v2 関数コード（`DefaultAzureCredential` + `SecretClient`） |

## 使い方

### 1. インフラのデプロイ

```powershell
az login
az account show

terraform init
terraform plan
terraform apply
```

apply 前に Azure CLI でログインしておくこと。
`data.azurerm_client_config.current` の取得と、Terraform からの Key Vault 初期シークレット作成に必要。

### 2. 関数コードのデプロイ

Azure Functions Core Tools（`func`）が必要。

```powershell
cd python/reader
func azure functionapp publish func-kv-reader-dev-seiwan --python
cd ../..

cd python/writer
func azure functionapp publish func-kv-writer-dev-seiwan --python
cd ../..
```

実際のコマンドは `terraform output verify_commands` に出力される。

### 3. 動作確認

```powershell
# Reader（最初は 503 が返ることがある — RBAC 反映 + KV reference 解決待ち）
curl https://func-kv-reader-dev-seiwan.azurewebsites.net/api/message
# → "Hello, World! (read-only function — secret loaded via Key Vault reference)"

# Writer の Function キーを取得
$KEY = az functionapp keys list --resource-group rg-func-kv-split-dev `
  --name func-kv-writer-dev-seiwan --query functionKeys.default --output tsv

# シークレットを更新
curl -X POST "https://func-kv-writer-dev-seiwan.azurewebsites.net/api/secret?code=$KEY" `
  -H "Content-Type: application/json" `
  -d '{\"value\": \"Updated-World\"}'

# Key Vault 側で確認
az keyvault secret show --vault-name kv-fnsplit-dev-seiwan --name greeting-name --query value --output tsv
# → Updated-World

# Reader を再起動して Key Vault reference のキャッシュをリセット
az functionapp restart --resource-group rg-func-kv-split-dev --name func-kv-reader-dev-seiwan

# 反映確認
curl https://func-kv-reader-dev-seiwan.azurewebsites.net/api/message
# → "Hello, Updated-World! ..."
```

## 学習ポイント

### A. 関数単位で権限分離は **できない**

`@app.route(...)` で定義した関数はすべて同じ Function App = 同じ MI = 同じ RBAC。
だから今回は Function App ごと分けた。
1 Function App で済むケース（権限が同じ場合）と比較しながら理解すると良い。

### B. Reader は SDK を一切使わない

Reader の `function_app.py` は `azure-identity` も `azure-keyvault-secrets` も
import していない。Key Vault references が Functions ランタイム側で解決され、
関数コードからは **「ただの環境変数」** に見えるため。
これがいわゆる「**コードに Key Vault の存在を意識させない**」パターン。

### C. RBAC 反映遅延と Key Vault references の解決タイミング

Function App 作成直後（〜数分）、または再起動直後は、Key Vault reference が
解決されておらず、環境変数の値が **参照式そのままの文字列** になることがある。

```
GREETING_NAME = "@Microsoft.KeyVault(SecretUri=https://.../secrets/greeting-name)"
```

Reader コードはこの状態を検出して 503 を返している。
解決手段は「待つ」または「`az functionapp restart`」。

### D. Writer が値を更新しても Reader には自動で反映されない

Key Vault references は **解決結果をキャッシュ** している（最大 24 時間）。
Writer でシークレットを更新した直後に Reader を呼んでも、Reader 側は古い値を
返すことがある。即座に反映させるには Reader の再起動が必要。

これはセキュリティ要件として「シークレット rotation を即時反映」したい場合の
**設計上の落とし穴** として重要。SDK 経由で都度取得する方法と比較すると違いが見える。

### E. Function キー保護の挙動

Writer は `auth_level=FUNCTION` のため、`?code=<key>` クエリパラメータ
（または `x-functions-key` ヘッダー）が必須。
キーは Function App 作成時に自動生成され、`az functionapp keys list` で取得できる。
キーの管理は Function App ごと（= Reader 側のキーでは Writer は叩けない）。

## 後片付け

```powershell
terraform destroy
```

`purge_soft_delete_on_destroy = true` を設定しているので、Key Vault は destroy 時に
完全削除される（次回 apply で同名再作成が可能）。
本番ではこの設定を外し、ソフトデリート期間を活用すること。
