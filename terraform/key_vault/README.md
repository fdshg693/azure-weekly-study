# Key Vault プロジェクト

Azure Key Vault を作成し、RBAC でアクセス制御を行い、サンプルシークレットを格納する独立した Terraform プロジェクト。

## 構成

- **リソースグループ** (`azurerm_resource_group`) — すべてのリソースを束ねるコンテナ
- **Key Vault** (`azurerm_key_vault`) — Standard SKU、RBAC 認証、ソフトデリート 7 日、パージ保護無効、パブリックアクセス有効
- **RBAC ロール割り当て** (`azurerm_role_assignment`) — `azurerm_client_config` で取得した現在のユーザーに `Key Vault Secrets Officer` を付与
- **シークレット** (`azurerm_key_vault_secret`) — 動作確認用サンプル（RBAC 反映を待つため `depends_on` でロール割り当て後に作成）

## ファイル

| ファイル | 役割 |
| --- | --- |
| [provider.tf](provider.tf) | `azurerm ~> 3.0` プロバイダー設定 |
| [variables.tf](variables.tf) | Key Vault 名・SKU・シークレット名／値・タグ等の入力変数（バリデーション付き、シークレット値は `sensitive`） |
| [main.tf](main.tf) | リソースグループ / Key Vault / RBAC ロール割り当て / シークレットの定義 |
| [outputs.tf](outputs.tf) | Key Vault URI、シークレット情報、`az keyvault` 系の動作確認コマンドを出力 |

## 主な変数（デフォルト値）

- `location` = `Japan East`
- `resource_group_name` = `rg-key-vault-dev`
- `key_vault_name` = `kv-simple-dev-seiwan`（英字始まり、英数字とハイフン、3-24 文字、グローバル一意）
- `key_vault_sku` = `standard`（`standard` / `premium` のみ許可）
- `secret_name` = `sample-secret`
- `secret_value` = `Hello-from-KeyVault!`（`sensitive`）

## 使い方

```powershell
terraform init
terraform plan
terraform apply
```

apply 前に Azure CLI でログインしておくこと（`data.azurerm_client_config.current` がログイン中の Principal を参照して RBAC ロールを付与する）。

```powershell
az login
az account show
```

デプロイ後、`terraform output key_vault_uri` で Key Vault の URI を確認できる。`terraform output verify_commands` には `az keyvault` 系の動作確認コマンドがまとまっている：

```powershell
# シークレット一覧
az keyvault secret list --vault-name <kv-name> --output table

# シークレット値の取得
az keyvault secret show --vault-name <kv-name> --name sample-secret --query value --output tsv
```

## RBAC に関する注意

`enable_rbac_authorization = true` のため、Key Vault のシークレット操作にはアクセスポリシーではなく Azure RBAC ロールが必要。このプロジェクトは現在のユーザーに `Key Vault Secrets Officer` を自動で付与する。他のユーザー／サービスプリンシパルから操作する場合は別途ロール割り当てを追加すること。

## 後片付け

```powershell
terraform destroy
```

`purge_protection_enabled = false` なので、ソフトデリート期間中に同名で再作成したい場合は `az keyvault purge --name <kv-name>` で完全削除できる。
