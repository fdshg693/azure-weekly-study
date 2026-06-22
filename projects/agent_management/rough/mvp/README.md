# MVP 実装プラン（確定版）

[research/](../../research/) の調査を踏まえ、**推奨設定をすべて採用して確定**した MVP のプラン。
論点の背景は [research/decisions/01-open-decisions.md](../../research/decisions/01-open-decisions.md)・
[research/decisions/02-architecture-review.md](../../research/decisions/02-architecture-review.md) を参照。

- 詳細: [data-and-api.md](./data-and-api.md)（データモデル＋REST API 契約）、[structure.md](./structure.md)（構成・バージョン・起動）

---

## 確定した設定（推奨どおり）

| # | 論点 | 確定 |
|---|---|---|
| A-1 | エージェント定義の正本 | **Foundry**（`agents.create_version`） |
| A-2 | PostgreSQL の役割 | **エージェント↔会話インデックス＋アプリメタ**に限定 |
| A-3 | メッセージ本文を Postgres に持つ | **持たない**（本文は Foundry conversation が正本） |
| B-1 | MVP でストリーミング | **しない**（1 リクエスト＝1 完成レスポンス） |
| B-2 | ストリーミング実現方法 | （発展）`EventSource` のカスタムドライバ自作 |
| C-1 | IaC | **Bicep** |
| C-2 | ロール割当を IaC に含める | **含める**（`prompt_agent` の `az` 依存を解消） |
| D-1 | 利用者認証 | **なし**（ローカル単一利用者）。`created_by` 列だけ将来用に保持 |
| D-2 | バック→Foundry 認証 | **DefaultAzureCredential**（ローカルは `az login`） |
| D-3 | バック→Postgres 認証 | **パスワード**（`learn/db/simple` と同型） |
| E-1 | フロント配信 | **dev サーバー別オリジン＋CORS**（ローカル） |
| E-2 | オーケストレーション | **Taskfile** |
| E-3 | Cycle.js 依存 | **最新を npm 取得＋Vite**。ローカルコピーは参照専用 |
| F-1 | 更新（U）の見せ方 | **最新バージョンのみ**表示。更新＝内部的に新バージョン作成 |
| F-2 | 削除（D）の意味 | **エージェントごと削除**（`agents.delete`） |

---

## スコープ（MVP の線引き）

**やる**

- エージェント CRUD（AOAI・prompt agent・ツール非対応）
  - C: `agents.create_version` ＋ `PromptAgentDefinition(model, instructions)`
  - R: `agents.list` / `agents.get`（一覧・詳細）
  - U: 新バージョン作成にマップ（UI 上は「編集」）
  - D: `agents.delete`
- モデル選択: `deployments.list()` の結果から選ぶだけ
- チャット（非ストリーミング）: 会話作成 → メッセージ送信 → 完成応答表示 → 会話一覧／削除
- IaC（Bicep）: Foundry 一式＋PostgreSQL＋ロール割当
- ローカル: Docker PostgreSQL ＋ uvicorn ＋ Vite dev サーバー

**やらない（発展課題として明示的に切り出す）**

- トークンのストリーミング表示（→ `EventSource` カスタムドライバ）
- メッセージ本文の Postgres 二重保存（client-managed 履歴）
- エージェントのバージョン履歴 UI、`delete_version`
- 利用者認証（Entra/MSAL）、Entra 認証パスワードレス DB 接続
- ツール対応・複数モデル種別

---

## アーキテクチャ（確定像）

```text
[Cycle.js SPA  (Vite dev, :5173)]
  │  REST/JSON
  ▼
[FastAPI backend (uvicorn, :8000)]
  ├─ DefaultAzureCredential ─► [Foundry Agent Service]
  │                              ├ agents (定義・バージョン)        ＝正本
  │                              └ conversations / responses (履歴) ＝正本(既定Cosmos)
  └─ psycopg ─► [PostgreSQL (Docker :5432 / Azure Flexible Server)]
                 └ conversations インデックス（agent_name ↔ foundry_conversation_id）＝アプリ固有の正本
```

データの所在と API マッピングの詳細は [data-and-api.md](./data-and-api.md)。

---

## 実装フェーズ（この順で進める）

各フェーズは「動かして確かめる」まで含める（CLAUDE.md: 一度デプロイして終わりにしない）。

1. **インフラ（Bicep）** — [structure.md](./structure.md) の `infra/`
   - AIServices アカウント（kind=AIServices）＋ Foundry プロジェクト＋モデルデプロイ（AOAI, 既定 `gpt-4.1-mini`）
   - PostgreSQL Flexible Server ＋ 論理 DB（`learn/db/simple` 流用）
   - **ロール割当（自分への Foundry User）を Bicep に内包**
   - ローカル DB は Docker（`docker-compose.yml` or Task）
   - 確認: `az deployment` でデプロイ → `deployments.list()` がモデルを返す
2. **バックエンド骨組み** — `backend/`
   - FastAPI ＋ 設定（`.env`）＋ Foundry クライアント ＋ `GET /api/models`（`deployments.list`）
   - エージェント CRUD（`/api/agents` 系、Postgres 未接続でも動く部分）
   - 確認: curl で agent 作成→一覧→削除が通る
3. **PostgreSQL 接続** — `backend/app/db.py`
   - `conversations` テーブルの作成（マイグレーション＝起動時 DDL で可）
   - 会話の作成・一覧・削除を Foundry ＋ Postgres にまたいで実装
   - 確認: 会話を作ると Postgres に行が増え、削除すると Foundry とともに消える
4. **チャット（非ストリーミング）**
   - `POST /api/conversations/{id}/messages`（ユーザー発話追加 → `responses.create` → 完成応答）
   - `GET /api/conversations/{id}/messages`（Foundry の conversation items を読み戻す）
   - 確認: 2 ターン会話で履歴が維持される（`prompt_agent` の France→首都 と同型）
5. **フロントエンド（Cycle.js）** — `frontend/`
   - Vite scaffold ＋ `@cycle/run`/`@cycle/dom`/`@cycle/http`/`@cycle/state`/`xstream`
   - 画面: エージェント一覧／作成・編集フォーム／チャット（会話一覧＋スレッド＋入力）
   - MVI ＋ onion state、HTTP ドライバで backend を叩く
   - 確認: ブラウザから CRUD とチャットが一周

---

## 「叩いて変化を体験する」シナリオ（CLAUDE.md ガードレール）

デプロイ後、操作で結果が変わることを体験するところまでやる。

- **instructions を変えて編集 → 新バージョンが作られ、同じ質問への応答が変わる**
  （Foundry のバージョニングと「更新＝新版」を体感）。
- **自分の Foundry User ロールを `az` で剥奪 → チャットが 403 → 付け直すと通る**
  （認証と認可の分離。auth/k8s トピックで既習の型を Foundry で再確認）。
- **モデルデプロイを別モデルに変える → 応答の傾向が変わる／無いモデルだとエラー**（リージョン・デプロイ依存）。
- **会話を削除 → Postgres の一覧から消え、Foundry の conversation も消える**
  （アプリインデックスと Foundry 正本の対応を体感）。
- **Postgres のファイアウォール規則を出し入れ → 接続が通る⇄拒否**（`learn/db/simple` と同型）。

---

## ドキュメント更新（実装時に対応）

- `projects/agent_management/README.md`：実装後に手順・学習の流れを更新。
- `KNOWLEDGE.md` 新規作成：このプロジェクトで初出の概念のみ
  （FRP/ストリーム/ドライバ＝Cycle.js、Responses API/conversations/agent version、CORS、`StreamingResponse`〔発展〕等）。
- このプロジェクトは `learn/` 配下ではないため `learn/{topic}/CLAUDE.md` の対象外（`projects/` 直下）。
</content>
