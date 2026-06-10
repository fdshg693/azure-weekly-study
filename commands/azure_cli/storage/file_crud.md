# BLOB（ファイル）の操作

コンテナ内のBLOB（ファイル）に対する作成・読み取り・更新・削除の操作。
ファイルを置く先のコンテナやストレージアカウント自体の操作は次を参照。

- コンテナの操作: `container.md`
- ストレージアカウント（リソース）の操作: `account.md`

---

## 作成（アップロード）

- ローカルファイルをBLOBストレージにアップロード

```shell
az storage blob upload `
  --account-name <storage-account-name> `
  --container-name <container-name> `
  --name <blob-name> `
  --file <local-file-path>
```

- 同じ名前で新しいファイルをアップロード（上書き）

```shell
az storage blob upload `
  --account-name <storage-account-name> `
  --container-name <container-name> `
  --name <blob-name> `
  --file <new-file-path> `
  --overwrite
```

## 読み取り

- ファイルをダウンロード

```shell
az storage blob download `
  --account-name <storage-account-name> `
  --container-name <container-name> `
  --name <blob-name> `
  --file <local-file-path>
```

- ファイル情報を表示

```shell
az storage blob show `
  --account-name <storage-account-name> `
  --container-name <container-name> `
  --name <blob-name>
```

- コンテナ内のファイル一覧を表示

```shell
az storage blob list `
  --account-name <storage-account-name> `
  --container-name <container-name>
```

## 削除

- ファイルを削除

```shell
az storage blob delete `
  --account-name <storage-account-name> `
  --container-name <container-name> `
  --name <blob-name>
```

- コンテナ内の全ファイルを削除

```shell
az storage blob delete-batch `
  --account-name <storage-account-name> `
  --source <container-name>
```
