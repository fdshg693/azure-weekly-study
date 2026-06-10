# Azure Functions の学習

Azure Functions を中心に、**サーバーレスのトリガー／バインディング**と、Functions から他の
Azure リソース（Storage / Key Vault）へ**どう安全にアクセスするか**を、プロジェクトごとに
サブフォルダで分割して学ぶ。
各プロジェクトは「**最小構成で 1 つの仕組みを体験 → 設定を出し入れして因果を確かめる**」という、
このリポジトリ共通の方針に従う。構築・実行はユーザー自身が行い、AI が Azure 上で実行することはない。

- `./REFERENCES.md`：トピック共通の参考ドキュメント

## 使用技術

- 環境構築は **Terraform（`azurerm ~> 3.0`）**。auth トピックが Bicep 中心だったのに対し、
  func は Terraform でリソースを定義する（`*.tf` を役割ごとにファイル分割）。
- ランタイムは **Python v2 プログラミングモデル**（`@app.route` / `@app.blob_trigger` のデコレーター記法）。
- 関数コードのデプロイは **Azure Functions Core Tools（`func azure functionapp publish`）**。
- コマンドの集約は `justfile`（blob_logger）または `terraform` 直叩き（func_keyvault）。
- 監視は **Application Insights（Workspace-based）** を各プロジェクトで作成。

## プロジェクト一覧

### blob_logger

`./blob_logger`

`func` の最初のプロジェクト。**Blob トリガー × Blob 出力バインディング**を最小構成で体験する。
`uploads` コンテナへのアップロードで Function が発火し、`logs` コンテナに `<元ファイル名>.log` を
書き出す。**SDK も Managed Identity も使わず「バインディングだけ」で入出力を完結**させているのが肝で、
関数本体はログ文字列を組み立てて `logblob.set(...)` するだけ（Blob の読み書きコードを一行も書かない）。
接続は `AzureWebJobsStorage` を使い回すので追加の接続設定も RBAC も不要。設定を出し入れして確かめる点は
**入力と出力でコンテナを分ける理由（同一コンテナだと無限ループ）**、**Consumption Plan の Blob トリガーは
ポーリングゆえ発火が数十秒〜数分遅延すること**。発展課題として Append Blob 追記・Event Grid トリガー化・
identity ベース接続でのキーレス化を README に明記（＝この時点では未実施）。

### func_keyvault

`./func_keyvault`

`func` の 2 つ目のプロジェクト。blob_logger の「バインディングだけ」から一歩進み、**Managed Identity ×
Key Vault × RBAC スコープ × Functions の auth level** をまとめて扱う。核心は **「関数単位では RBAC を
分けられない」**（同一 Function App 内の関数は同じ MI を共有する）ため、**Reader（読み取り専用）と
Writer（更新可能）を別々の Function App に分離**すること。Reader は System-Assigned MI に
`Key Vault Secrets User` を与え、シークレットを **Key Vault reference 経由で app setting に注入**するので
**コードは KV の SDK を一切 import しない**（環境変数に見える）。Writer は `Key Vault Secrets Officer` を
与え、`DefaultAzureCredential` + `SecretClient` の **SDK でシークレットを更新**、`auth_level=FUNCTION` の
Function キーで保護する。設定を出し入れして確かめる点は、**RBAC 反映遅延／Key Vault reference 未解決時の
503**、**KV reference のキャッシュ（最大 24 時間）ゆえ Writer の更新が Reader に即時反映されない落とし穴**、
**Function キーは App ごと**。

## 学習した概念

- Blob トリガー＋入出力バインディング（SDK を書かずに入出力を完結させる発想）
- バインディングのトリガー対象と出力先を分ける設計（無限ループ回避）
- Consumption Plan の Blob トリガーがポーリングで遅延すること
- Functions ランタイムストレージ（`AzureWebJobsStorage`）の使い回し
- System-Assigned Managed Identity による Functions → 他リソースのキーレスアクセス
- Key Vault references（app setting への注入）と SDK 直接取得の使い分け／トレードオフ
- RBAC スコープを「関数単位では分けられない／App 単位で分ける」設計判断
- Key Vault RBAC ロール（Secrets User / Officer）と最小権限
- Functions の auth level（anonymous / function）と Function キー
- Python v2 プログラミングモデル（デコレーター記法）、Terraform での Functions 一式の構築
- Application Insights（Workspace-based）での監視

## まだ学習できていない概念（次プロジェクトの候補）

- **Event Grid ベースの Blob トリガー**（ポーリング遅延の解消 / blob_logger 発展課題）
- **identity ベース接続でのキーレス化**（`<CONN>__serviceUri` + Storage Blob Data ロール）
- Append Blob への追記など、出力バインディングでは扱えない書き込みパターン（SDK 必須ケース）
- HTTP トリガー以外の各種トリガー（Queue / Timer / Service Bus / Cosmos DB 等）
- Durable Functions（オーケストレーション）
- Premium / Dedicated プランと VNet 統合・プライベートエンドポイント連携
- CI/CD（GitHub Actions 等）からの関数デプロイ
- スロット（デプロイスロット）を使ったブルーグリーン/段階リリース
