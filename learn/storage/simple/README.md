# Storage Accounts (Simple) プロジェクト

Azure Storage Account の**静的Webサイトホスティング機能**を使い、`index.html` と `error.html` だけを匿名公開する Terraform プロジェクト。それ以外のファイル（例: `sample.txt`）は private コンテナに置かれ、SAS トークン経由でしかアクセスできない。

## 設計のポイント — 「他のファイルが絶対に公開されない」ことの担保

公開ルートを次の 2 段構えで封じている。

1. **静的Webサイトの専用エンドポイント (`*.z.web.core.windows.net`) は `$web` コンテナの中身しか配信しない**
   `$web` 以外のコンテナにアップロードしたファイルは、この Web エンドポイントから見えない。本プロジェクトでは `$web` には `index.html` と `error.html` の **2 ファイルだけ** をアップロードする。

2. **`allow_nested_items_to_be_public = false` で Blob エンドポイントからの匿名アクセスも禁止**
   Storage Account レベルでこのフラグを `false` に固定すると、どのコンテナも public-blob / public-container アクセスタイプに設定できなくなる。誰かが後から手作業でコンテナを公開しようとしても Azure 側が拒否する。
   静的Webサイト機能は Web エンドポイントという別経路で動くため、このフラグを `false` にしても通常通り動作する。

結果として、`$web` 以外にアップロードしたファイル（本プロジェクトの `sample.txt` を含む）は **SAS トークンを発行されない限り誰からもアクセスできない**。

## 構成

- **リソースグループ** (`azurerm_resource_group`)
- **Storage Account** (`azurerm_storage_account`) — `static_website` 有効、`allow_nested_items_to_be_public = false`
- **`$web` コンテナの Blob** — `index.html`, `error.html`（匿名公開）
  - `$web` コンテナ自体は `static_website` を有効にすると Azure が自動作成するため、Terraform から `azurerm_storage_container` で作成しない
- **private コンテナ** (`azurerm_storage_container` / `container_access_type = "private"`)
- **private コンテナ内の Blob** — `sample.txt`（匿名アクセス不可）
- **SAS トークン** (`data.azurerm_storage_account_sas`) — private Blob の一時共有用、読み取り専用 / HTTPS / 24 時間有効

## ファイル

| ファイル | 役割 |
| --- | --- |
| [provider.tf](provider.tf) | `azurerm ~> 3.0` プロバイダー設定 |
| [variables.tf](variables.tf) | 入力変数（Storage Account 名、コンテナ名、index/error html のパスなど） |
| [main.tf](main.tf) | リソースグループ + Storage Account（`static_website` ブロック含む） |
| [web.tf](web.tf) | `$web` コンテナへの `index.html` / `error.html` アップロード |
| [container.tf](container.tf) | private コンテナ、private Blob、SAS トークン生成 |
| [outputs.tf](outputs.tf) | 静的Webサイト URL、private Blob の SAS 付き URL |
| [terraform.tfvars.example](terraform.tfvars.example) | `terraform.tfvars` のテンプレート |
| [index.html.example](index.html.example) | 静的Webサイト用 index.html のサンプル |
| [error.html.example](error.html.example) | 静的Webサイト用 404 ページのサンプル |
| [sample.txt.example](sample.txt.example) | private コンテナにアップロードするファイルのサンプル |

## 主な変数（デフォルト値）

- `storage_account_name` = `maikumastorageacct`
- `container_name` = `example-container`（private コンテナの名前）
- `blob_name` = `sample.txt`
- `local_file_path` = `./sample.txt`
- `index_document` = `index.html` / `index_html_local_path` = `./index.html`
- `error_document` = `error.html` / `error_html_local_path` = `./error.html`
- `sas_token_expiry` = `24h`

リージョンとリソースグループ名はコード内（[main.tf](main.tf)）に直書き（`Japan East` / `rg-storage-example`）。

## 使い方

### justfile を使う場合（推奨）

[justfile](justfile) に主要コマンドをまとめてある。`just --list` で一覧を確認できる。

```powershell
just up              # setup（.example をコピー） → init → apply をまとめて実行
just url             # 静的Webサイトの URL を表示
just open            # ブラウザで開く
just test-public     # index.html に HTTP アクセスして応答を確認
just test-404        # 存在しないパスにアクセス → error.html が返ることを確認
just test-private-blocked  # private Blob に SAS なしでアクセス → 拒否されることを確認
just sas-url         # private Blob の SAS 付き URL を表示
just test-private-sas      # SAS 付きでアクセス → 取得できることを確認
just destroy         # インフラを削除
```

### 手動で実行する場合

1. アップロード対象ファイルを準備：

   ```powershell
   Copy-Item index.html.example index.html
   Copy-Item error.html.example error.html
   Copy-Item sample.txt.example sample.txt
   ```

2. Terraform を実行：

   ```powershell
   terraform init
   terraform plan
   terraform apply
   ```

3. 静的Webサイトの URL を取得してブラウザで開く：

   ```powershell
   terraform output -raw static_website_url
   ```

   → `index.html` が表示される。存在しないパスにアクセスすると `error.html` が返る。

4. 非公開ファイル（`sample.txt`）に一時的にアクセスしたい場合は SAS 付き URL を使う：

   ```powershell
   terraform output -raw blob_url_with_sas
   ```

## 公開範囲の挙動確認

| アクセス先 | 結果 |
| --- | --- |
| `https://<account>.z.web.core.windows.net/` | `index.html` を返す |
| `https://<account>.z.web.core.windows.net/notfound` | `error.html` を返す（HTTP 404） |
| `https://<account>.blob.core.windows.net/$web/index.html`（匿名） | **アクセス拒否**（Blob エンドポイントは匿名公開を許可していない） |
| `https://<account>.blob.core.windows.net/example-container/sample.txt`（匿名） | **アクセス拒否** |
| 上記 + SAS トークン | アクセス可能（24 時間） |

## 後片付け

```powershell
terraform destroy
```
