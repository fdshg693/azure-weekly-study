# データモデル ＆ REST API 契約（確定版）

[research/decisions/02-architecture-review.md](../../research/decisions/02-architecture-review.md) の「データモデルの所在」を
MVP 用に具体化したもの。

---

## データの所在（誰が正本か）

| データ | 正本 | 取得・操作方法 | Postgres に持つ |
|---|---|---|---|
| エージェント定義（model / instructions / version） | **Foundry** | `agents.create_version` / `get` / `get_version` / `list` / `delete` | ✗ |
| メッセージ本文・実行履歴 | **Foundry**（既定 Cosmos） | `conversations.create` / `GET /openai/v1/conversations/{id}/items` / `responses.create` | ✗ |
| モデルデプロイ一覧 | **Foundry** | `deployments.list()` | ✗ |
| **エージェント↔会話のインデックス** | **アプリ** | 下記 `conversations` テーブル | **✓** |

> Foundry には「あるエージェントに紐づく会話を一覧する」API が無いため、`conversation_id` を
> アプリが控える必要がある。ここが PostgreSQL の唯一かつ正当な役割（MVP）。

---

## PostgreSQL スキーマ（MVP）

起動時 DDL（冪等な `CREATE TABLE IF NOT EXISTS`）で十分。マイグレーションツールは MVP では不要。

```sql
-- 会話インデックス：Foundry の conversation を「どのエージェントの会話か」で引けるようにする
CREATE TABLE IF NOT EXISTS conversations (
    id                      BIGGENERATED ALWAYS AS IDENTITY PRIMARY KEY,  -- ※下の注記参照
    foundry_conversation_id TEXT        NOT NULL UNIQUE,   -- Foundry の conversation id
    agent_name              TEXT        NOT NULL,          -- Foundry のエージェント名
    title                   TEXT        NOT NULL DEFAULT '',-- 先頭ユーザー発話の冒頭など
    created_by              TEXT,                          -- 将来の認証用（MVP は NULL）
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_conversations_agent
    ON conversations (agent_name, created_at DESC);
```

> 注記: PK は `BIGINT GENERATED ALWAYS AS IDENTITY`（上の `BIGGENERATED` は誤記しない）。
> エージェント単位のメタ（エイリアス・タグ・論理削除・並び順）は **任意**。必要になったら
> `agents_meta(agent_name PK, alias, tags, sort_order, ...)` を足す。MVP は `conversations` のみで成立。

---

## REST API 契約（FastAPI）

オリジンはローカルで別（フロント :5173 / バック :8000）なので **CORS を許可**。すべて JSON。

### モデル

| メソッド | パス | 実装 | レスポンス |
|---|---|---|---|
| GET | `/api/models` | `deployments.list()` | `[{ "name": "gpt-4.1-mini", ... }]` |

### エージェント CRUD

| メソッド | パス | 実装 | 備考 |
|---|---|---|---|
| GET | `/api/agents` | `agents.list()` | `[{ name, latest_version, model, instructions }]` |
| POST | `/api/agents` | `agents.create_version(name, PromptAgentDefinition(model, instructions))` | body `{ name, model, instructions }` |
| GET | `/api/agents/{name}` | `agents.get` ＋ `get_version` | 最新バージョンの定義詳細 |
| PUT | `/api/agents/{name}` | `agents.create_version(...)` | **新バージョン作成にマップ**。body `{ model, instructions }` |
| DELETE | `/api/agents/{name}` | `agents.delete(name, force=True)` | エージェントごと削除 |

### 会話（エージェントにぶら下がる）

| メソッド | パス | 実装 | 備考 |
|---|---|---|---|
| GET | `/api/agents/{name}/conversations` | Postgres `SELECT ... WHERE agent_name=$1 ORDER BY created_at DESC` | 会話一覧 |
| POST | `/api/agents/{name}/conversations` | `conversations.create()` → Postgres `INSERT` | `{ id, title }` を受け取り保存。返り値に `foundry_conversation_id` |
| DELETE | `/api/conversations/{id}` | Foundry `conversations.delete` ＋ Postgres `DELETE` | 両方から消す |

### メッセージ（チャット本体・非ストリーミング）

| メソッド | パス | 実装 | 備考 |
|---|---|---|---|
| GET | `/api/conversations/{id}/messages` | Foundry conversation items 取得 | 履歴の読み戻し（role/content） |
| POST | `/api/conversations/{id}/messages` | `conversations.items.create`（user 発話）→ `responses.create(conversation=cid, agent_reference={name})` | body `{ content }` → 完成した assistant 応答を返す |

> `responses.create` の呼び出しは `extra_body={"agent_reference": {"name": <agent_name>, "type": "agent_reference"}}`。
> 実コードの型は `azure-ai-projects/samples/agents/sample_agent_basic.py`（非ストリーミング）が手本。
> ストリーミング版（発展）は `sample_agent_stream_events.py`。

---

## 代表フロー（チャット 1 ターン・非ストリーミング）

```text
フロント            バックエンド                          Foundry                Postgres
  │ POST /agents/{n}/conversations                          │                      │
  ├──────────────────►│ conversations.create() ────────────►│ (cid 発行)           │
  │                   │ INSERT conversations(cid, n, title) ─┼─────────────────────►│
  │◄── {id, fcid} ────┤                                      │                      │
  │ POST /conversations/{id}/messages {content}              │                      │
  ├──────────────────►│ items.create(user) ─────────────────►│                      │
  │                   │ responses.create(agent_reference) ──►│ (応答生成・履歴追記) │
  │◄── {assistant} ───┤◄─────────────────────────────────────┤                      │
```
</content>
