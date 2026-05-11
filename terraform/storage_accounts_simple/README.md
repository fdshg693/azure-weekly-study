# Storage Accounts (Simple) プロジェクト

Azure Storage Account にローカルファイルを Blob としてアップロードし、読み取り専用の SAS トークン付き URL を発行する独立した Terraform プロジェクト。

## 構成

- **リソースグループ** (`azurerm_resource_group`) — すべてのリソースを束ねるコンテナ
- **Storage Account** (`azurerm_storage_account`) — Standard / GRS レプリケーション、StorageV2
- **Storage Container** (`azurerm_storage_container`) — `private` アクセス
- **Storage Blob** (`azurerm_storage_blob`) — ローカルファイル (`sample.txt`) を Block Blob としてアップロード（`filemd5()` で内容変更を検知）
- **SAS トークン** (`data.azurerm_storage_account_sas`) — 読み取り専用、HTTPS のみ、`timestamp()` + `timeadd()` で 24 時間有効

## ファイル

| ファイル | 役割 |
| --- | --- |
| [provider.tf](provider.tf) | `azurerm ~> 3.0` プロバイダー設定 |
| [variables.tf](variables.tf) | Storage Account 名・コンテナ名・Blob 名・ローカルファイルパス・SAS 有効期間の入力変数（バリデーション付き） |
| [main.tf](main.tf) | リソースグループおよび Storage Account の定義 |
| [container.tf](container.tf) | コンテナ、Blob アップロード、SAS トークン生成データソースの定義 |
| [outputs.tf](outputs.tf) | Storage Account ID、SAS トークン付き Blob URL（`sensitive`）を出力 |
| [terraform.tfvars.example](terraform.tfvars.example) | `terraform.tfvars` のテンプレート |
| [sample.txt.example](sample.txt.example) | アップロード対象ファイルのサンプル（`sample.txt` にリネームして使用） |

## 主な変数（デフォルト値）

- `storage_account_name` = `maikumastorageacct`（小文字英数字のみ、3-24 文字、グローバル一意）
- `container_name` = `example-container`
- `blob_name` = `sample.txt`
- `local_file_path` = `./sample.txt`
- `sas_token_expiry` = `24h`（Go duration 形式：`24h` / `168h` / `720h` など）

リージョンとリソースグループ名はコード内（[main.tf](main.tf)）に直書きされている（`Japan East` / `rg-storage-example`）。

## 使い方

1. アップロード対象のファイルを準備する（デフォルト名は `sample.txt`）：

   ```powershell
   Copy-Item sample.txt.example sample.txt
   ```

2. Terraform を実行：

   ```powershell
   terraform init
   terraform plan
   terraform apply
   ```

3. SAS トークン付き Blob URL を取得：

   ```powershell
   terraform output -raw blob_url_with_sas
   ```

   この URL をブラウザに貼り付けるか `curl` で叩くと、Blob の内容を読み取れる（24 時間限定）。

## SAS トークンの仕様

[container.tf](container.tf) で定義する SAS は次の通り：

- `resource_types`: `object` のみ（個別 Blob へのアクセス、コンテナ一覧などは不可）
- `services`: `blob` のみ
- `permissions`: `read` のみ（書き込み・削除・一覧などは不可）
- `https_only = true`
- 有効期間: `timestamp()` から `var.sas_token_expiry`（デフォルト 24h）

`timestamp()` を使っているため `terraform plan` を実行するたびに SAS が再生成される点に注意。

## 後片付け

```powershell
terraform destroy
```
