# db（マネージドデータベース / PaaS）トピック — ユーザーのレベル感と次プロジェクトの目安

このトピックは **マネージドデータベース（PaaS、主役は PostgreSQL Flexible Server）** を
主役に、`learn/db/{name}/` の各プロジェクトで段階的に学ぶ。共通方針はリポジトリ全体と同じ
「**一般概念／最小構成 → 実装 → 設定を出し入れして因果を確かめる**」「**構築・実行は
ユーザー自身、AI は Azure 上で実行しない**」。
次プロジェクトの設計の目安（ロードマップの正本）は [PLAN.md](./PLAN.md) を参照。

> 関連: 「**VM 上に自前で DB を立てる**」側は vm トピック（IaaS）。こちらは**マネージド（PaaS）**を
> 主役に「運用を任せる代わりに何が制約になるか」を学ぶ。k8s `workload-identity` で触れた
> **PostgreSQL の Entra 認証 / キーレス接続**の延長でもある（→ Step 2 で本格化）。

## プロジェクト一覧

### `simple` — マネージド PostgreSQL を 1 つ立てて繋ぐ（PLAN Step 1）
Bicep で **PostgreSQL Flexible Server（Burstable B1ms / v16 / パスワード認証 / パブリック
エンドポイント）** と論理 DB `appdb` を作り、ローカルの小さな Python スクリプト（`connect.py`,
`psycopg`）から **テーブル作成 → INSERT → SELECT** を一周。`.env` に接続情報を置き、
`just init-env` が PGPASSWORD をランダム生成、`just deploy` が PGHOST を書き戻す。
- **因果実験**: **ファイアウォール規則は Bicep に書かず** justfile で出し入れ。作成直後は許可 IP が
  0 件 → どこからも繋がらない（パブリックエンドポイントはあるのに通れない）。`allow-my-ip`/
  `deny-my-ip` で自分の IP を足す／外すと接続が通る⇄拒否される。**「マネージド DB はデフォルトで
  閉じている」「経路はあるが許可制」** を体感（vm の NSG ルール出し入れと同じ型）。
- 課金感覚: VM の `deallocate`（割り当て解除で課金停止）に当たる気軽な停止が無く、
  使い終わったら `destroy` で消す、を強調。

## 学習済みの概念
マネージド DB（PaaS）と Flexible Server（コンピュート／ストレージ分離）、
**サーバー > データベース > ロール**の階層、接続文字列の構成要素（host/port/dbname/user/password/sslmode と
`PG*` 環境変数）、**パブリックエンドポイント + ファイアウォール規則による「許可制」到達制御**
（NSG との対比）、**TLS 必須（sslmode=require）**、Burstable SKU とマネージド DB の課金感覚
（停止の概念が VM と違う）。`psycopg` でのローカル最小 CRUD。

## まだ触れていない主要概念（PLAN の続き）
- **パスワードレス認証**: Microsoft Entra 認証 + Managed Identity（`DefaultAzureCredential`）、
  Entra ロール／GRANT の付け外しで「**認証と認可は別**」を体感（Step 2 `entra-auth`、
  k8s `workload-identity` の DB 接続と同筋）。
- **閉域化**: Private Endpoint + Private DNS Zone（Step 3、storage `private_endpoint` を DB に適用）。
- **運用**: バックアップ / ポイントインタイムリストア（PITR）/ vCore・ストレージのスケール変更
  （Step 4）。
- **別パラダイム**: Cosmos DB（NoSQL・パーティションキー・整合性レベル・RU 課金）、
  リードレプリカ／ジオレプリケーション（Step 5）。
