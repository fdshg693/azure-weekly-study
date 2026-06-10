# Blob トリガーで「アップロードをログに記録する」プロジェクト

Storage の **`uploads` コンテナにファイルがアップロードされるたびに** Function が起動し、
**`logs` コンテナに別ファイル（`<元のファイル名>.log`）としてログを書き出す** シンプルな学習用プロジェクト。

「Blob トリガー × Blob 出力バインディング」を最小構成で体験することを目的にしている。
SDK も Managed Identity も使わず、**バインディングだけ** で入出力を完結させているのがポイント。

## 仕組み

```
[ user ] --upload--> (uploads コンテナ)
                          │  Blob トリガーが発火
                          ▼
                   [ Function App ]  ← logging.info で App Insights にもトレース
                          │  Blob 出力バインディング
                          ▼
                     (logs コンテナ) ──> <ファイル名>.log
```

- `uploads/sample.txt` をアップロード → `logs/sample.txt.log` が作られる
- ログの中身（例）:

  ```
  [2026-06-11T03:21:09Z] uploaded blob='uploads/sample.txt' size=18 bytes
  ```

## なぜ入力と出力でコンテナを分けるのか

トリガーが監視している `uploads` コンテナに **ログ自身を書き込んでしまうと、
書いたログが再びトリガーを発火させ、無限ループ** になる。
出力先を別コンテナ（`logs`）にすることでこれを防いでいる。これは Blob トリガー設計の典型的な落とし穴。

## 作られるもの

- リソースグループ（`rg-func-blob-logger-dev`）
- Storage Account × 1（`StorageV2` / LRS）
  - `uploads` コンテナ（入力 / トリガー監視対象）
  - `logs` コンテナ（出力 / ログ書き出し先）
- App Service Plan × 1（Linux Consumption Y1）
- Log Analytics Workspace + Application Insights（Workspace-based）
- Function App（Blob トリガー / Python v2）

## ファイル

| ファイル | 役割 |
| --- | --- |
| [provider.tf](provider.tf) | `azurerm ~> 3.0` プロバイダー設定 |
| [variables.tf](variables.tf) | リソース名（グローバル一意）・コンテナ名・Python バージョン等 |
| [resource_group.tf](resource_group.tf) | リソースグループ |
| [storage.tf](storage.tf) | Storage Account + `uploads` / `logs` コンテナ |
| [service_plan.tf](service_plan.tf) | Consumption Plan |
| [application_insights.tf](application_insights.tf) | Log Analytics Workspace + Application Insights |
| [function_app.tf](function_app.tf) | Function App（`AzureWebJobsStorage` 経由で入出力） |
| [outputs.tf](outputs.tf) | 動作確認コマンド等の出力 |
| [python/function_app.py](python/function_app.py) | Blob トリガー + Blob 出力バインディングの関数本体 |
| [python/host.json](python/host.json) | Functions ホスト設定（拡張バンドル v4） |
| [python/requirements.txt](python/requirements.txt) | `azure-functions` のみ（SDK 不要） |
| [python/local.settings.json.example](python/local.settings.json.example) | ローカル実行用設定の雛形 |
| [justfile](justfile) | デプロイ・アップロード・ログ確認のコマンド集 |

## 使い方

### 1. インフラのデプロイ

```powershell
az login
az account show

just init
just plan
just apply
```

### 2. 関数コードのデプロイ

Azure Functions Core Tools（`func`）が必要。

```powershell
just deploy
```

`just up`（= `apply` → `deploy`）で一括実行も可能。

### 3. 動作確認

```powershell
# uploads コンテナにテストファイルをアップロード
just upload file="sample.txt"

# 数十秒待ってから logs コンテナを確認
#（Consumption Plan の Blob トリガーはポーリングのため発火まで遅延がある）
just logs

# 生成されたログの中身を確認
just show-log name="sample.txt.log"
```

`just demo` でアップロード → 30 秒待機 → ログ確認まで一気に流せる。
関数のリアルタイムログを見たいときは `just tail`（ログストリーム）。

## 学習ポイント

### A. バインディングだけでコードはほぼロジック無し

`function_app.py` は Blob を読み書きする処理を **一行も書いていない**。
入力（`func.InputStream`）も出力（`func.Out[str]`）もバインディングが面倒を見るので、
関数は「ログ文字列を組み立てて `logblob.set(...)` するだけ」になる。
SDK を使う書き方（`BlobServiceClient` で自前読み書き）と比較すると、バインディングの威力が分かる。

### B. 接続は `AzureWebJobsStorage` を使い回す

トリガー・出力ともに接続名 `AzureWebJobsStorage` を指定している。
Terraform で Storage Account をランタイムストレージに指定しているため、
この接続文字列が自動で app settings に入り、**追加の接続設定も RBAC も不要**。

> 本番でキーレス化（接続文字列を使わず Managed Identity に）したい場合は、
> identity ベース接続（`<CONN>__serviceUri`）+ `Storage Blob Data Owner` ロールに
> 切り替える。これは発展課題。

### C. Consumption Plan の Blob トリガーは「遅延」する

Consumption Plan の標準 Blob トリガーは **ポーリング方式** のため、
アップロードから発火まで数十秒〜数分かかることがある（大量ファイルだと取りこぼし検知も遅れる）。
即時性が必要なら **Event Grid ベースの Blob トリガー** に切り替えるのが定石。

### D. トリガー対象と出力先を分ける（無限ループ回避）

「なぜ入力と出力でコンテナを分けるのか」で述べた通り、
出力を監視対象コンテナに書くとループする。Blob トリガー設計の基本。

## 発展課題（このプロジェクトの次に）

- **1 つのログファイルに追記**: ファイルごとに `.log` を作るのではなく、
  Append Blob（`logs/upload-log.log`）に 1 行ずつ追記する。出力バインディングは
  上書きなので、Append Blob は SDK（`azure-storage-blob`）+ Managed Identity が必要になる。
- **Event Grid トリガー化**: 遅延をなくす（学習ポイント C）。
- **キーレス化**: identity ベース接続 + Storage Blob Data ロール（学習ポイント B）。

## 後片付け

```powershell
just destroy
```
