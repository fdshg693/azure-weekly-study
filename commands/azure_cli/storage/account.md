# ストレージアカウント（リソース）の操作

ストレージサービスの土台となるストレージアカウントの作成・一覧・削除や、
接続に必要なキー・接続文字列の取得など。

- コンテナの操作: `container.md`
- 個々のファイル（BLOB）の操作: `file_crud.md`

---

## 作成

- ストレージアカウントを作成

```shell
az storage account create `
  --name <storage-account-name> `
  --resource-group <resource-group-name> `
  --location japaneast `
  --sku Standard_LRS
```

| オプション | 説明 |
| --- | --- |
| `--sku` | 冗長性。`Standard_LRS`（ローカル冗長） / `Standard_GRS`（地理冗長） など |
| `--location` | リージョン。`japaneast` / `japanwest` など |

## 読み取り

- ストレージアカウント一覧を表示

```shell
az storage account list `
  --resource-group <resource-group-name> `
  --output table
```

- ストレージアカウントの情報を表示

```shell
az storage account show `
  --name <storage-account-name> `
  --resource-group <resource-group-name>
```

- アクセスキーを取得

```shell
az storage account keys list `
  --account-name <storage-account-name> `
  --resource-group <resource-group-name> `
  --output table
```

- 接続文字列を取得

```shell
az storage account show-connection-string `
  --name <storage-account-name> `
  --resource-group <resource-group-name>
```

### アクセスキー・接続文字列とは？

ストレージアカウントの中身（コンテナや BLOB）を操作するには「このアカウントの正当な利用者だ」と証明する必要があります。その認証情報がアクセスキーと接続文字列です。

| 用語 | 中身 | イメージ |
| --- | --- | --- |
| **アクセスキー (access key)** | アカウント全体への**フルアクセス権**を持つ秘密の文字列。`key1` / `key2` の 2 本が自動発行される | 部屋の「マスターキー」そのもの |
| **接続文字列 (connection string)** | 接続先情報（アカウント名・エンドポイント）＋アクセスキーを 1 本にまとめた文字列 | マスターキー＋住所をまとめた「設定セット」 |

- **接続文字列 = アクセスキー + 接続先情報**。つまり接続文字列の中にアクセスキーが含まれており、どちらも漏れるとアカウントを丸ごと操作されてしまう機密情報です。

### 使い所

- **アプリ（プログラム）から接続するとき**：アプリの SDK は接続文字列 1 本を渡すだけで接続できるため、アプリの設定（環境変数や Key Vault）に**接続文字列**を入れるのが一般的です。
- **CLI / スクリプトで操作するとき**：`az storage blob` などのコマンドに `--account-key`（アクセスキー）や `--connection-string` を渡して認証します。
- **キーが 2 本ある理由（key1 / key2）**：サービスを止めずにキーを更新するため。`key1` を使い続けながら `key2` に切り替え → `key1` を再生成、とローテーション（定期的なキー入れ替え）ができます。

> ⚠️ **注意**：アクセスキー・接続文字列は「全権限を持つパスワード」と同じです。コードに直書きせず環境変数や Azure Key Vault で管理し、漏れたら必ず再生成してください。より安全に権限を絞りたい場合は、期限・権限を限定できる **SAS（Shared Access Signature）** や **Microsoft Entra ID 認証** の利用が推奨されます。

## 削除

- ストレージアカウントを削除（中のコンテナ・ファイルごと削除される）

```shell
az storage account delete `
  --name <storage-account-name> `
  --resource-group <resource-group-name>
```
