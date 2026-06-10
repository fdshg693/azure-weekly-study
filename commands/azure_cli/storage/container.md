# コンテナの操作

BLOB（ファイル）を入れる入れ物であるコンテナの作成・一覧・削除など。
コンテナはストレージアカウントの中に作成する。

- 個々のファイル（BLOB）の操作: `file_crud.md`
- ストレージアカウント（リソース）の操作: `account.md`

---

## 作成

- コンテナを作成

```shell
az storage container create `
  --account-name <storage-account-name> `
  --name <container-name>
```

- 公開アクセスレベルを指定して作成（`off` / `blob` / `container`）

```shell
az storage container create `
  --account-name <storage-account-name> `
  --name <container-name> `
  --public-access blob
```

## 読み取り

- コンテナ一覧を表示

```shell
az storage container list `
  --account-name <storage-account-name> `
  --output table
```

- コンテナの情報を表示

```shell
az storage container show `
  --account-name <storage-account-name> `
  --name <container-name>
```

- コンテナの存在確認

```shell
az storage container exists `
  --account-name <storage-account-name> `
  --name <container-name>
```

## 削除

- コンテナを削除（中のファイルごと削除される）

```shell
az storage container delete `
  --account-name <storage-account-name> `
  --name <container-name>
```
