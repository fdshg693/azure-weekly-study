# 共通リファレンス：全体設計・認証・設定・構成

全ステップで参照する横断事項。個々のステップ文書はここを前提にする。

---

## 1. アーキテクチャ（確定像）

```text
[Cycle.js SPA  (Vite dev, :5173)]
  │  REST/JSON  （別オリジン → CORS 許可）
  ▼
[FastAPI backend (uvicorn, :8000)]
  ├─ DefaultAzureCredential ─► [Foundry Agent Service]
  │                              ├ agents        … 定義・バージョン      ＝正本
  │                              └ conversations / responses … 履歴・実行 ＝正本(既定 Cosmos)
  └─ psycopg ─► [PostgreSQL (Docker :5432 / Azure Flexible Server)]
                 └ conversations インデックス（agent_name ↔ foundry_conversation_id）＝アプリ固有の正本
```

- backend は **2 つの下流**（Foundry / Postgres）に対する薄いオーケストレータ。ビジネスロジックは最小。
- フロントは backend の REST しか知らない（Foundry SDK をフロントに持ち込まない）。

### 責務の分離（誰が何の正本か）

| データ | 正本 | backend の役割 |
|---|---|---|
| エージェント定義（model / instructions / version） | Foundry | SDK 呼び出しを REST に橋渡し |
| メッセージ本文・実行履歴 | Foundry（既定 Cosmos） | 同上（本文は Postgres に持たない） |
| モデルデプロイ一覧 | Foundry | `deployments.list()` をそのまま返す |
| エージェント↔会話インデックス | **アプリ（Postgres）** | 唯一の自前永続化。詳細は [common-schema-api.md](./common-schema-api.md) |

> Foundry に「エージェントに紐づく会話一覧」API が無いことが、Postgres を持つ唯一の理由。

---

## 2. 認証（3 経路）

| 経路 | 方式 | ローカルでの前提 |
|---|---|---|
| 利用者 → フロント/バック | **なし**（単一利用者）。`created_by` 列だけ将来用に保持 | — |
| backend → Foundry | **DefaultAzureCredential** | `az login` 済み＋自分に Foundry User ロール（ロールは step-1 の Bicep で付与） |
| backend → Postgres | **パスワード認証**（`learn/db/simple` と同型） | `.env` の `PG*` |

- ロール割当を IaC に内包したことで、`prompt_agent` で必要だった `az` での手動 grant が不要になる（step-1）。
- 「ロールを剥がすと 403 になる」体験は step-2 / step-4 の確認シナリオで回収する。

---

## 3. 設定（.env / 環境変数）

優先順位は **環境変数 > `.env` > 既定値**（CLAUDE.md 準拠）。`backend/.env.example` を雛形として配置、
実値の `.env` は GITIGNORE。`config.py` が一元的に読み込み、他モジュールは `config` 経由で参照する。

```dotenv
# Foundry
FOUNDRY_PROJECT_ENDPOINT=https://<account>.services.ai.azure.com/api/projects/<project>
FOUNDRY_MODEL_NAME=gpt-4.1-mini          # 既定で選ぶデプロイ名（フロントの選択肢のデフォルトにも使う）

# PostgreSQL（ローカル Docker の既定値）
PGHOST=localhost
PGPORT=5432
PGDATABASE=agent_mgmt
PGUSER=app
PGPASSWORD=                               # init で生成 or 手入力

# CORS
FRONTEND_ORIGIN=http://localhost:5173
```

> Foundry 系は `learn/foundry/prompt_agent/_config.py`、Postgres 系は `learn/db/simple` の `.env` と同名・同型を
> 踏襲し、既習プロジェクトとの差分を最小化する。

---

## 4. フォルダ構成（確定）

```text
agent_management/
├─ README.md                 # 既存（実装後に手順を更新）
├─ KNOWLEDGE.md              # 新規（初出概念のみ。§7 の用語表が下書き）
├─ Taskfile.yml              # 3 プロセス起動するため justfile ではなく Taskfile
├─ docker-compose.yml        # ローカル PostgreSQL
├─ research/ rough/ imple/   # 調査・確定プラン・本実装計画
│
├─ infra/                    # Bicep（IaC）          → step-1
│  ├─ main.bicep             # modules を束ねる
│  ├─ foundry.bicep          # AIServices アカウント＋プロジェクト＋モデルデプロイ
│  ├─ postgres.bicep         # PostgreSQL Flexible Server ＋論理 DB
│  └─ roles.bicep            # ロール割当（自分への Foundry User）
│
├─ backend/                  # FastAPI               → step-2〜4
│  ├─ requirements.txt
│  ├─ .env.example
│  └─ app/
│     ├─ main.py             # app・CORS・router 登録・起動時 DDL
│     ├─ config.py           # .env/環境変数の読み込み
│     ├─ foundry.py          # AIProjectClient / openai_client のラッパ
│     ├─ db.py               # psycopg 接続・conversations の CRUD・DDL
│     └─ routers/
│        ├─ models.py        # GET /api/models
│        ├─ agents.py        # /api/agents 系
│        └─ chat.py          # /api/.../conversations, /messages 系
│
└─ frontend/                 # Cycle.js（最新依存＋Vite） → step-5
   ├─ package.json / vite.config.js / index.html
   └─ src/
      ├─ main.js  app.js
      ├─ components/ { agentList.js, agentForm.js, chat.js }
      └─ api.js              # backend エンドポイントの request 生成
```

---

## 5. 依存バージョンの方針

- **フロント（最新を npm 取得）**: `@cycle/run` / `@cycle/dom` / `@cycle/http` / `@cycle/state` / `xstream`、ビルドは Vite。
  - 同梱の [cyclejs/](../cyclejs/)（TS 3.2.4 / RxJS 6 / Node 8 想定）は **参照専用**。アプリ依存には使わない。
- **バック**: Python 3.10+、`azure-ai-projects>=2.2.0`、`azure-identity`、`openai`、`fastapi`、`uvicorn`、`psycopg`、`python-dotenv`。
  - Python はルート直下 `.venv` を共有（CLAUDE.md）。`backend/requirements.txt` で依存を明示。
- **DB**: ローカル `postgres:16`（Docker）、Azure は PostgreSQL Flexible Server v16（`learn/db/simple` と同型）。

---

## 6. オーケストレーション（Taskfile）

3 プロセス（DB / backend / frontend）を起動するため justfile ではなく **Taskfile**（巨大ワンライナー回避）。

```text
task db:up        # docker compose で PostgreSQL 起動
task backend      # uvicorn app.main:app --reload（:8000）。起動時に DDL 実行
task frontend     # vite（:5173）
task dev          # まとめて起動（DB→backend→frontend）
task infra:deploy # az deployment group create -f infra/main.bicep（明示指示があるときのみ）
```

---

## 7. 用語（`KNOWLEDGE.md` の下書き：このプロジェクト初出のみ）

| 用語 | 一言 |
|---|---|
| Responses API | OpenAI 互換の応答生成 API。`responses.create` で 1 応答を得る |
| conversation | 複数ターンを束ねる入れ物。同じ id を渡すと履歴が連鎖（`prompt_agent/02_chat.py` の肝） |
| agent_reference | `responses.create` に `extra_body` で渡し、どのエージェント定義で応答するかを指定 |
| agent version | エージェントは不変。更新＝同名で `create_version` し新バージョンが増える |
| CORS | 別オリジン（:5173→:8000）の XHR を許可する仕組み。FastAPI の CORSMiddleware |
| FRP / ストリーム / ドライバ | Cycle.js の中核（副作用＝ドライバ、純粋関数＝main、データ＝ストリーム） |
| MVI / onion state | Cycle.js のアプリ設計（Model-View-Intent と入れ子状態管理） |
| `StreamingResponse`（発展） | FastAPI でトークンを逐次返す。MVP では未使用 |

---

## 8. ガードレール（CLAUDE.md 準拠）

- **実デプロイはユーザーの明示指示があるときのみ**。MVP 実装中はローカル（Docker DB＋既存 Foundry プロジェクト流用）で
  動作確認を進め、Azure への `infra:deploy` 適用は指示を待つ。
- 読み取り系コマンド（`deployments.list` 等）は原因調査として実行可。
- 各ステップで「設定を出し入れして因果を確かめる」ところまでやる（確認シナリオを各ステップに明記）。
