# 共通リファレンス：データモデル・スキーマ検討・REST API 契約

[rough/mvp/data-and-api.md](../rough/mvp/data-and-api.md) を、**SDK の実際の型を確認したうえで**実装可能な
契約まで詰めたもの。SDK は同梱コピー [azure-ai-projects/](../azure-ai-projects/) の `operations/_operations.py`・
`models/_models.py` を実地確認済み（下記「SDK 確認メモ」）。

---

## 1. SDK 確認メモ（設計に効く事実）

実コードを読んで確認した、API 設計を左右するポイント。

### 1-1. エージェント一覧は N+1 不要 — 最新版定義が埋め込まれている

`agents.list()` が返す `AgentDetails` は次の構造を持つ：

```text
AgentDetails
  ├ id, name, object
  └ versions: AgentObjectVersions
       └ latest: AgentVersionDetails
            ├ name, version, description, created_at, status
            └ definition: PromptAgentDefinition   ← model / instructions を含む
```

- つまり **一覧取得時点で各エージェントの `latest.definition.model` / `.instructions` が取れる**。
  `GET /api/agents` のために 1 件ずつ `get_version` を呼ぶ必要は **ない**（N+1 を回避できる）。
- `get` / `get_version` は **詳細（特定バージョン）取得**用に温存。MVP では `GET /api/agents/{name}` 詳細で使う。
- 一覧は `kind="prompt"` でフィルタする（MVP は prompt agent のみ。hosted/workflow/external を除外）。

### 1-2. メソッドシグネチャ（確認済み）

| 操作 | 実シグネチャ（要点） | 返り |
|---|---|---|
| 作成/更新 | `agents.create_version(agent_name=str, definition=PromptAgentDefinition(...))` | `AgentVersionDetails`（`.name/.version`） |
| 一覧 | `agents.list(kind="prompt", order="desc", limit=...)` | `ItemPaged[AgentDetails]` |
| 詳細 | `agents.get(agent_name=str)` → `AgentDetails` ／ `agents.get_version(agent_name, agent_version)` | `AgentDetails` / `AgentVersionDetails` |
| 削除 | `agents.delete(agent_name=str, force=True)` | `DeleteAgentResponse` |
| モデル一覧 | `deployments.list(deployment_type="ModelDeployment")` | `ItemPaged[ModelDeployment]`（`.name/.model_name/.model_version/.model_publisher`） |

- `PromptAgentDefinition(model=str, instructions=str)`（任意で `temperature` 等あり。MVP は 2 つだけ）。
- 会話・応答は **OpenAI 互換クライアント**（`project.get_openai_client()`）側：
  `openai.conversations.create(...)` / `openai.conversations.items.create(conversation_id=, items=[...])` /
  `openai.responses.create(conversation=cid, extra_body={"agent_reference": {"name":.., "type":"agent_reference"}})` /
  `openai.conversations.delete(conversation_id=)`。手本は
  [azure-ai-projects/samples/agents/sample_agent_basic.py](../azure-ai-projects/samples/agents/sample_agent_basic.py)。

### 1-3. 含意（API 設計への反映）

- `delete` の `force=True` は「バージョンが残っていてもエージェントごと消す」意。MVP の D（削除）はこれに一本化。
- 「更新＝新バージョン」なので backend の `PUT` は `create_version` に素直にマップでき、追加状態を持たない。
- モデル一覧はそのまま `name` を返せばフロントのセレクトに使える（`model_name`/`version` は補助表示用）。

---

## 2. PostgreSQL スキーマ検討

### 2-1. 設計方針

- **持つのは会話インデックスのみ**。メッセージ本文・エージェント定義は Foundry が正本なので複製しない。
- マイグレーションツールは MVP では使わず、**起動時に冪等 DDL**（`CREATE TABLE IF NOT EXISTS`）。
- `learn/db/simple` の接続・FW 規則の出し入れの型をそのまま踏襲（パスワード認証・パブリックエンドポイント）。

### 2-2. DDL（先に確定しておく。実装の決め打ち項目）

```sql
-- 会話インデックス：Foundry の conversation を「どのエージェントの会話か」で引けるようにする
CREATE TABLE IF NOT EXISTS conversations (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    foundry_conversation_id TEXT        NOT NULL UNIQUE,    -- Foundry の conversation id
    agent_name              TEXT        NOT NULL,           -- Foundry のエージェント名
    title                   TEXT        NOT NULL DEFAULT '',-- 先頭ユーザー発話の冒頭など
    created_by              TEXT,                           -- 将来の認証用（MVP は NULL）
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_conversations_agent
    ON conversations (agent_name, created_at DESC);
```

> rough 版の `BIGGENERATED` は誤記。正しくは `BIGINT GENERATED ALWAYS AS IDENTITY`（上で確定）。

### 2-3. 設計上の検討メモ

- **PK は内部 BIGINT、対外は `id`**。`foundry_conversation_id` は Foundry 側 id（`conv_...`）で UNIQUE 制約により二重登録を防ぐ。
- **`agent_name` に FK は張らない**（エージェントの正本は Foundry。RDB に外部キー先が無い）。
  → エージェント削除時の会話行は **アプリ側で明示的に掃除する**か、孤児を許容するかを決める必要あり（§4 の論点参照）。
- **論理削除は持たない**（MVP）。削除は物理 DELETE。必要になったら `agents_meta` テーブルを後付け（rough の注記どおり）。
- 並び順は `created_at DESC`（新しい会話が上）。インデックスもこの順に最適化。

---

## 3. REST API 契約（FastAPI）

別オリジン（:5173 / :8000）なので **CORS 許可**。すべて JSON。パスは `/api` プレフィクス。

### 3-1. モデル

| メソッド | パス | 実装 | レスポンス（案） |
|---|---|---|---|
| GET | `/api/models` | `deployments.list(deployment_type="ModelDeployment")` | `[{ name, model_name, model_version, publisher }]` |

### 3-2. エージェント CRUD

| メソッド | パス | 実装 | リクエスト / レスポンス |
|---|---|---|---|
| GET | `/api/agents` | `agents.list(kind="prompt")` → `versions.latest.definition` を展開 | `[{ name, latest_version, model, instructions }]`（§1-1 より N+1 不要） |
| POST | `/api/agents` | `create_version(name, PromptAgentDefinition(model, instructions))` | req `{ name, model, instructions }` → `{ name, version }` |
| GET | `/api/agents/{name}` | `agents.get` ＋必要なら `get_version` | 最新バージョンの定義詳細 |
| PUT | `/api/agents/{name}` | `create_version(name, PromptAgentDefinition(model, instructions))` | **新バージョン作成にマップ**。req `{ model, instructions }` → `{ name, version }` |
| DELETE | `/api/agents/{name}` | `agents.delete(name, force=True)` ＋（§4）会話行の掃除 | 204 |

### 3-3. 会話（エージェントにぶら下がる）

| メソッド | パス | 実装 | 備考 |
|---|---|---|---|
| GET | `/api/agents/{name}/conversations` | Postgres `SELECT ... WHERE agent_name=$1 ORDER BY created_at DESC` | 会話一覧 |
| POST | `/api/agents/{name}/conversations` | `openai.conversations.create()` → Postgres `INSERT` | req `{ title? }` → `{ id, foundry_conversation_id, title }` |
| DELETE | `/api/conversations/{id}` | `openai.conversations.delete` ＋ Postgres `DELETE` | 両方から消す。順序は §4 |

### 3-4. メッセージ（チャット本体・非ストリーミング）

| メソッド | パス | 実装 | 備考 |
|---|---|---|---|
| GET | `/api/conversations/{id}/messages` | Foundry conversation items 取得（id→fcid を Postgres 経由で解決） | 履歴の読み戻し（role/content） |
| POST | `/api/conversations/{id}/messages` | `items.create`（user 発話）→ `responses.create(conversation=fcid, agent_reference)` | req `{ content }` → 完成 assistant 応答 |

> `agent_reference` は `extra_body={"agent_reference": {"name": <agent_name>, "type": "agent_reference"}}`。
> `{id}`（アプリの BIGINT）→ `foundry_conversation_id` の解決は backend が Postgres で行う（フロントは Foundry id を意識しない）。

---

## 4. 決めておくべき論点（実装前に確定）

スキーマ／契約を成立させるため、コード着手前に答えを固定しておく事項。

1. **`agent_name` の一意性とエージェント↔会話の整合**
   - 採用：会話 POST 時に `agent_name` の存在を **Foundry の `get` で軽く検証**してから INSERT（孤児行の予防）。
2. **エージェント削除時の会話行**
   - 採用：`DELETE /api/agents/{name}` で **当該 `agent_name` の `conversations` 行も削除**（Foundry 会話までは消さない＝MVP では割り切り。
     体験シナリオは「会話単位の削除」で Foundry まで消すことを別途見せる）。要・README/KNOWLEDGE に明記。
3. **会話削除の順序とべき等性**
   - 採用：**Foundry → Postgres の順**で削除。Foundry 側が既に無い（404）場合も握りつぶして Postgres を消し、結果整合に倒す。
4. **`title` の決め方**
   - 採用：POST 時に `title` 未指定なら空文字。先頭ユーザー発話の冒頭から後で埋める案は発展（MVP は空 or クライアント指定）。
5. **エラー方針**
   - 採用：Foundry 認証失敗は **403/401 をそのまま透過**（「ロール剥奪で 403」体験のため）。Postgres 断は 503。
     入力不備は 422（FastAPI 既定）。
6. **ページング**
   - MVP は省略（`agents.list`/会話一覧とも全件返す前提。件数は学習用途で小さい）。発展で `limit/before` を露出。

---

## 5. 代表フロー（チャット 1 ターン・非ストリーミング）

```text
フロント            バックエンド                                  Foundry                Postgres
  │ POST /agents/{n}/conversations                                  │                      │
  ├──────────────────►│ (n の存在を get で検証)                     │                      │
  │                   │ openai.conversations.create() ─────────────►│ (fcid 発行)          │
  │                   │ INSERT conversations(fcid, n, title) ───────┼─────────────────────►│
  │◄── {id, fcid} ────┤                                             │                      │
  │ POST /conversations/{id}/messages {content}                     │                      │
  ├──────────────────►│ id→fcid 解決(SELECT) ───────────────────────┼─────────────────────►│
  │                   │ items.create(user, fcid) ──────────────────►│                      │
  │                   │ responses.create(conversation=fcid, ref) ──►│ (応答生成・履歴追記) │
  │◄── {assistant} ───┤◄────────────────────────────────────────────┤                      │
```
