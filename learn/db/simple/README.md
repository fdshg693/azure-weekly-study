# Step 1: `simple` — マネージド PostgreSQL を 1 つ立てて繋ぐ

db トピックの最初のプロジェクト（[../PLAN.md](../PLAN.md) の Step 1）。
**マネージド PostgreSQL（Flexible Server, PaaS）** を Bicep で 1 台作り、ローカルの小さな
Python スクリプトから接続して**テーブル作成 → INSERT → SELECT** を一周する。
vm トピックの「自前で OS から面倒を見る DB（IaaS）」と対比し、ここでは
**「運用（パッチ／バックアップ／可用性）を Azure に任せる代わりに、何が制約になるか」**
を体で覚えるのが狙い。最初の制約として **「マネージド DB はデフォルトで閉じている」** を体感する。

## 目的（このステップで体感すること）

- マネージド DB を動かす最小要素（**Flexible Server / 論理データベース**）と、
  **「サーバー > データベース > ロール」** の階層・**接続文字列の構成要素**を理解する。
- **ファイアウォール規則を出し入れして因果を確かめる**:
  - 作成直後は許可 IP が 0 件 → **どこからも繋がらない**（パブリックエンドポイントは
    あるのに通れない）。
  - 自分の IP を**足すと通る**、**外すと拒否される**。
- パブリックエンドポイント + ファイアウォールという「**経路はあるが許可制**」の守り方を知る
  （閉域化＝Private Endpoint は Step 3、パスワードレス認証は Step 2）。

## 前提ツール

- [Azure CLI](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli)（`az login` 済み）
- [Just](https://github.com/casey/just)
- Python 3.10+（`just venv` がルート直下の共有 `.venv` を作って `psycopg` を入れる）

## 構成されるリソース（`main.bicep`）

| リソース | 名前 | 役割 |
|---|---|---|
| PostgreSQL Flexible Server | `pg-dbsimple-<一意文字列>` | 主役。Burstable `Standard_B1ms` / v16 / **パスワード認証** / パブリックエンドポイント |
| 論理データベース | `appdb` | サーバー内に作る 1 つのデータベース |

> リソースグループ: `rg-db-learn-simple`（東日本）。
> **ファイアウォール規則は Bicep に含めない**（因果実験のため justfile で出し入れする）。

---

## 実行手順

すべてこの `simple` ディレクトリで実行する。

### 0. 依存の準備（venv と .env）
```powershell
just venv       # ルート直下の共有 .venv を作り psycopg を入れる
just init-env   # .env を作成。PGPASSWORD をランダム生成
```

### 1. デプロイ
`.env` のパスワードを渡してサーバーと DB を作る。数分かかる。完了後 `PGHOST` が
`.env` に自動で書き込まれる。
```powershell
just deploy
```
> この時点では**まだ繋がらない**（許可 IP が 0 件）。次で自分の IP を開ける。

### 2. 自分の IP を開けて接続
```powershell
just allow-my-ip   # 現在のグローバル IP を許可するファイアウォール規則を追加
just connect       # テーブル作成 → INSERT → SELECT。version/件数が表示される
```
`just connect` を繰り返すと `visits` の行が 1 つずつ増える（操作で結果が変わるのを体感）。

---

### 実験: ファイアウォール規則で到達を切り替える
```powershell
just show-fw       # 現在の許可規則を確認（ClientIP があるはず）
just deny-my-ip    # 自分の IP の許可を外す
just connect       # → 接続拒否 / タイムアウト（DB は動いているのに届かない）
just allow-my-ip   # 許可を戻す
just connect       # → また繋がる
```
到達を決めていたのが **「ファイアウォールの許可」** だったことを対比で確認する。
**「マネージド DB はデフォルトで閉じている」**＝パブリックエンドポイントを持っていても、
明示的に許可した IP からしか通れない、という守り方を体感する
（vm トピックの **NSG ルール出し入れ**と同じ型。あちらは VM、こちらはマネージド DB）。

### 補助コマンド
```powershell
just my-ip      # 今の自分のグローバル IP
just status     # サーバーの状態（起動状況・バージョン・FQDN）
```

### 3. 後片付け（必ず実行）
```powershell
just destroy
```
> マネージド DB は**立てっぱなしでコンピュート課金が続く**。実験が終わったら必ず削除する
> （IaaS の `deallocate` のような「割り当て解除で課金停止」は無く、止めたいなら削除か
> サーバー停止が必要）。

## 補足

- このプロジェクトは**パスワード認証**で繋ぐ。次の Step 2（`entra-auth`）で
  **Microsoft Entra 認証によるパスワードレス接続**に置き換え、「認証と認可は別」を体感する
  （k8s `workload-identity` の DB 接続と同じ筋）。
- 閉域化（**Private Endpoint + Private DNS Zone**）は Step 3、バックアップ／PITR／スケールは
  Step 4（[../PLAN.md](../PLAN.md)）。
- 新出の用語・概念は [KNOWLEDGE.md](./KNOWLEDGE.md)、構成図・実験フローは [MERMAID.md](./MERMAID.md) を参照。
