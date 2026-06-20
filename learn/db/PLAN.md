# データベース 学習プラン — 何から作るか

このファイルは db トピックの**プロジェクト設計の目安（ロードマップの正本）**。
このトピックはまだプロジェクトが無いので、ここでは「最初の最小構成 → どう深化させるか」を定める。
方針はリポジトリ共通（[../CLAUDE.md](../CLAUDE.md)）どおり:
「**一般概念／最小構成 → 実装 → 設定を出し入れして因果を確かめる**」「**構築・実行はユーザー自身が行い、AI は Azure 上で実行しない**」。

> 関連トピック: 「**VM 上に自前で DB を立てる**」側は [../vm/PLAN.md](../vm/PLAN.md)（IaaS）。
> こちらの db トピックは **マネージド DB（PaaS）** を主役にし、「運用を任せる代わりに何が制約になるか」を学ぶ。
> k8s トピックの `workload-identity` で触れた **PostgreSQL の Entra 認証 / キーレス接続**の延長でもある。

---

## 1. このトピックで学びたいこと（ゴール像）

Azure のマネージドデータベースは選択肢が多い。まず**サービスの選び分け**の地図を持つことを最初のゴールにする。

- **Azure SQL Database**（SQL Server 系 PaaS）/ **Azure Database for PostgreSQL（Flexible Server）** / **MySQL** /
  **Cosmos DB**（NoSQL・グローバル分散）の役割分担。最初は 1 つに絞る（PostgreSQL 推奨。k8s で既出のため接続しやすい）。
- **接続とネットワーク**: パブリックエンドポイント + ファイアウォール規則 vs **Private Endpoint**（storage トピックで既習の閉域化を DB に適用）。
- **認証**: パスワード認証 vs **Microsoft Entra 認証**（パスワードレス / Managed Identity）。auth・k8s トピックの RBAC をここに接続。
- **スケールと階層**: vCore / DTU、コンピュートとストレージの分離、バックアップ・PITR（ポイントインタイムリストア）。
- **可用性**: ゾーン冗長、レプリカ、フェイルオーバーの考え方（触りだけ）。

## 2. 推奨ロードマップ（やさしい順）

各プロジェクトは `learn/db/{name}/` に置く想定。「**1 プロジェクト = 主役の概念 1〜2 個**」に絞る。

### Step 1 — `simple`（マネージド DB を 1 つ立てて繋ぐ）
**主役**: マネージド PostgreSQL（Flexible Server）の作成と接続の最小ループ。
- Bicep で PostgreSQL Flexible Server を作り、ローカル（`psql` / 小さな Python スクリプト）から接続してテーブル作成・INSERT/SELECT。
- **因果を確かめる実験**: **ファイアウォール規則**から自分の IP を外す → 接続が拒否される、足す → 通る、を観察。
  「マネージド DB はデフォルトで閉じている」を体感。
- KNOWLEDGE: サーバー / データベース / ロールの階層、接続文字列の構成要素。

### Step 2 — `entra-auth`（パスワードレス接続が主役）
**主役**: Microsoft Entra 認証による DB ログインのキーレス化。
- パスワード認証を廃し、**Entra 管理者 + Managed Identity**（ローカルは `DefaultAzureCredential`）でトークン接続。
- **因果を確かめる実験**: DB 側の Entra ロール／GRANT を付け外し → 接続成立・クエリ可否が変わる。
  「**認証（トークン取得）と認可（DB 内の権限）は別**」を体感（k8s `workload-identity` の DB 接続と同じ筋）。

### Step 3 — `private-endpoint`（閉域化が主役）
**主役**: Private Endpoint + Private DNS Zone による DB の閉域化。
- storage トピックの `private_endpoint` と同じ型を DB に適用。VNet 内の VM / コンテナからは到達、外からは拒否。
- **因果を確かめる実験**: パブリックアクセスを無効化 → ローカルからは繋がらず、VNet 内クライアントからは繋がる対比。

### Step 4 — `backup-restore`（運用が主役）
**主役**: バックアップ / ポイントインタイムリストア / スケール変更。
- データを入れた後に**特定時刻へリストア**して別サーバーに復元、差分を確認。
- **因果を確かめる実験**: vCore / ストレージをスケールアップ／ダウンし、停止時間や料金感覚を観察。保持期間を変えて PITR 可能範囲が変わるのを見る。

### Step 5（発展）— `cosmos` / レプリカ・読み取りスケール
- **Cosmos DB** で NoSQL・パーティションキー・整合性レベル・RU 課金という別パラダイムに触れる。
- リードレプリカ／ジオレプリケーションで読み取りスケールと地理冗長を体感。

## 3. 進め方のメモ

- 各プロジェクトに共通構成（`README.md` / `KNOWLEDGE.md` / `justfile` または `Taskfile.yml`）を置く。複雑になったら Taskfile。
- **PostgreSQL に統一**すると、k8s `workload-identity` / 将来の vm トピックと接続文字列・認証の話が地続きになり学習効率が良い。
- マネージド（PaaS）と自前運用（IaaS, → vm トピック）の対比を意識し、「何を Azure に任せ、何を失うか」を毎回言語化する。
- 最初のプロジェクトを 1 つ追加したタイミングで `learn/db/CLAUDE.md` に習熟度を記録する。
