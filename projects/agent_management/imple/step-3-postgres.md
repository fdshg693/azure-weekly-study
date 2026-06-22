# Step 3 — PostgreSQL 接続（会話インデックス＋会話 CRUD）

backend に Postgres を足し、**エージェント↔会話のインデックス**を成立させる。これは chat（step-4）の土台。
ここではまだメッセージ送信は実装せず、「会話を作る／一覧する／削除する」が Foundry と Postgres を
またいで動くところまでをやる。

> スキーマ・論点の確定版は [common-schema-api.md](./common-schema-api.md) §2・§4。接続方針は
> [common-architecture.md](./common-architecture.md) §2/§3。

---

## 目的

- `app/db.py` を作り、psycopg でローカル Docker PostgreSQL に接続。
- **起動時に冪等 DDL**（`CREATE TABLE IF NOT EXISTS conversations`）を実行（マイグレーションツール不要）。
- 会話の **作成・一覧・削除** を Foundry（`openai.conversations.*`）と Postgres にまたいで実装。

---

## 成果物（ファイル）

```text
backend/app/
├─ db.py                 # psycopg 接続プール・起動時 DDL・conversations の CRUD 関数
├─ main.py               # 起動時に db.init()（DDL）を呼ぶよう追記
└─ routers/
   └─ chat.py            # 会話 CRUD（メッセージ系は step-4 で同ファイルに追加）
```

---

## 設計メモ

### db.py

- 接続：`config.pg_*` から DSN を組む。psycopg の **コネクションプール**を 1 つ持ち、リクエストごとに借り受ける。
- DDL：`init()` で [common-schema-api.md](./common-schema-api.md) §2-2 の `CREATE TABLE IF NOT EXISTS` ＋ INDEX を実行。冪等。
- 公開関数（薄い CRUD）：
  - `insert_conversation(foundry_conversation_id, agent_name, title, created_by=None) -> row`
  - `list_conversations(agent_name) -> [row]`（`ORDER BY created_at DESC`）
  - `get_conversation(id) -> row | None`（`id → foundry_conversation_id` 解決に使う。step-4 で多用）
  - `delete_conversation(id) -> deleted_count`
  - `delete_conversations_by_agent(agent_name)`（エージェント削除時の掃除。§4-2）
- パラメータは必ずプレースホルダ（`%s`）でバインド（SQL インジェクション回避）。

### routers/chat.py（会話 CRUD 部分）

| エンドポイント | 実装の要点 |
|---|---|
| `GET /api/agents/{name}/conversations` | `db.list_conversations(name)` をそのまま返す |
| `POST /api/agents/{name}/conversations` | (1) `agents.get(name)` で存在検証 → (2) `openai.conversations.create()` で fcid 発行 → (3) `db.insert_conversation(fcid, name, title)` → `{id, foundry_conversation_id, title}` |
| `DELETE /api/conversations/{id}` | (1) `db.get_conversation(id)` で fcid 解決 → (2) `openai.conversations.delete(fcid)`（404 は握りつぶす）→ (3) `db.delete_conversation(id)` |

### agents.py との連結（step-2 の DELETE を補完）

- `DELETE /api/agents/{name}` に **`db.delete_conversations_by_agent(name)` を追加**（[common-schema-api.md](./common-schema-api.md) §4-2 の採用方針）。
  Foundry の会話本体までは消さない割り切りを README/KNOWLEDGE に明記する。

### main.py

- アプリ起動イベントで `db.init()`（DDL）を実行。Postgres 断時は明確に失敗させ、原因を切り分けやすくする。

---

## 設計上の検討（再掲・要確定）

- **削除順序**：Foundry → Postgres（[common-schema-api.md](./common-schema-api.md) §4-3）。Foundry 側 404 は無視して Postgres を消し結果整合に倒す。
- **存在検証**：会話 POST 時に `agents.get` で `agent_name` を検証してから INSERT（孤児行の予防、§4-1）。
- **トランザクション**：単一 INSERT/DELETE なので明示トランザクションは最小。Foundry と Postgres の二相は張れないため、
  失敗時の補償（片側だけ残る）はログに残し、結果整合で許容（MVP）。

---

## 確認シナリオ

```text
POST /api/agents/{name}/conversations {title}      → {id, foundry_conversation_id}; Postgres に 1 行増える
GET  /api/agents/{name}/conversations              → 作った会話が新しい順に出る
DELETE /api/conversations/{id}                     → Postgres から消え、Foundry の conversation も消える
DELETE /api/agents/{name}                          → その agent の会話行がまとめて消える（§4-2）
```

- 体験：**会話を作ると Postgres の行が増え、削除すると Foundry とともに消える**（アプリインデックスと正本の対応）。
- 体験：**Postgres の FW 規則／Docker 停止で接続断 → 503**（`learn/db/simple` と同型の「許可制／閉じている」感覚）。

---

## このステップの DoD

- [ ] 起動時 DDL で `conversations` テーブルが冪等に作られる
- [ ] 会話の作成・一覧・削除が Foundry＋Postgres をまたいで動く
- [ ] エージェント削除時に該当会話行が掃除される
- [ ] `id ↔ foundry_conversation_id` の解決関数が用意され step-4 が乗れる
