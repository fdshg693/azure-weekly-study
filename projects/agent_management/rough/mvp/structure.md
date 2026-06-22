# 構成・バージョン・起動（確定版）

MVP のフォルダ／ファイル構成、依存バージョン、ローカル起動手順。

---

## フォルダ構成

```text
agent_management/
├─ README.md                 # 既存（実装後に手順を更新）
├─ KNOWLEDGE.md              # 新規（初出概念のみ）
├─ Taskfile.yml              # ★justfile ではなく Taskfile（3 プロセス起動するため）
├─ docker-compose.yml        # ローカル PostgreSQL
├─ research/                 # 既存（事前調査）
├─ plan/mvp/                 # 本プラン
│
├─ infra/                    # ★Bicep（IaC）
│  ├─ main.bicep             # オーケストレーション（modules を束ねる）
│  ├─ foundry.bicep          # AIServices アカウント＋プロジェクト＋モデルデプロイ
│  ├─ postgres.bicep         # PostgreSQL Flexible Server ＋論理 DB
│  └─ roles.bicep            # ★ロール割当（自分への Foundry User）
│
├─ backend/                  # FastAPI
│  ├─ requirements.txt       # fastapi, uvicorn, azure-ai-projects>=2.2, azure-identity, openai, psycopg, python-dotenv
│  ├─ .env.example
│  └─ app/
│     ├─ main.py             # FastAPI app・CORS・router 登録・起動時 DDL
│     ├─ config.py           # .env/環境変数の読み込み（優先順: env > .env > 既定）
│     ├─ foundry.py          # AIProjectClient / openai_client のラッパ
│     ├─ db.py               # psycopg 接続・conversations の CRUD・DDL
│     └─ routers/
│        ├─ models.py        # GET /api/models
│        ├─ agents.py        # /api/agents 系
│        └─ chat.py          # /api/.../conversations, /messages 系
│
└─ frontend/                 # Cycle.js（最新依存＋Vite）
   ├─ package.json
   ├─ vite.config.js
   ├─ index.html             # #main-container を持つ
   └─ src/
      ├─ main.js             # run(main, {DOM, HTTP, state})
      ├─ app.js              # ルート component（MVI＋onion state）
      ├─ components/
      │  ├─ agentList.js     # 一覧・選択・削除
      │  ├─ agentForm.js     # 作成／編集（編集＝新バージョン）
      │  └─ chat.js          # 会話一覧＋スレッド＋入力（非ストリーミング）
      └─ api.js              # backend のエンドポイント定義（HTTP ドライバ用 request 生成）
```

> 共通ファイル構成は CLAUDE.md の方針に沿う。`justfile` ではなく **Taskfile**（DB/バック/フロントの 3 起動があり
> 巨大ワンライナーを避けたいため）。`PLAN.md` 相当はこの `plan/mvp/` が担う。

---

## 依存バージョンの方針

- **フロント（最新を npm 取得）**: `@cycle/run` / `@cycle/dom` / `@cycle/http` / `@cycle/state` / `xstream`、ビルドは Vite。
  - リポジトリ同梱の `cyclejs/`（TS 3.2.4 / RxJS 6 / Node 8 想定）は**参照専用**。アプリ依存には使わない。
- **バック**: Python 3.10+、`azure-ai-projects>=2.2.0`、`azure-identity`、`openai`、`fastapi`、`uvicorn`、`psycopg`、`python-dotenv`。
  - Python はルート直下 `.venv` 共有（CLAUDE.md）。`backend/requirements.txt` で依存を明示。
- **DB**: ローカル `postgres:16`（Docker）、Azure は PostgreSQL Flexible Server v16（`learn/db/simple` と同型）。

---

## 設定（.env / 環境変数）

`backend/.env.example` に雛形を置く（実値の `.env` は GITIGNORE 済み）。優先順位は **環境変数 > `.env` > 既定**。

```dotenv
# Foundry
FOUNDRY_PROJECT_ENDPOINT=https://<account>.services.ai.azure.com/api/projects/<project>
FOUNDRY_MODEL_NAME=gpt-4.1-mini          # 既定で選ぶデプロイ名（フロントの選択肢にも出す）

# PostgreSQL（ローカル Docker の既定値）
PGHOST=localhost
PGPORT=5432
PGDATABASE=agent_mgmt
PGUSER=app
PGPASSWORD=                               # init で生成 or 手入力

# CORS
FRONTEND_ORIGIN=http://localhost:5173
```

---

## ローカル起動（Taskfile レシピのイメージ）

```text
task db:up        # docker compose で PostgreSQL 起動
task backend      # uvicorn app.main:app --reload（:8000）。起動時に DDL 実行
task frontend     # vite（:5173）
task dev          # 上記をまとめて起動（DB→backend→frontend）
```

- バック→Foundry は `DefaultAzureCredential`。事前に **`az login`** が必要。
- バック→Postgres はパスワード認証（`.env` の `PG*`）。
- フロントは別オリジンなので backend 側で **CORS（`FRONTEND_ORIGIN`）を許可**。

---

## Azure デプロイ（IaC）

```text
task infra:deploy   # az deployment group create -f infra/main.bicep
```

- `main.bicep` が `foundry.bicep` / `postgres.bicep` / `roles.bicep` を束ねる。
- リソースの構成は `learn/foundry/prompt_agent/00_provision.py`（AIServices＋project＋deployment）と
  `learn/db/simple`（Postgres Flexible Server）を Bicep に翻訳する形。
- **ロール割当（自分への Foundry User）を `roles.bicep` に内包** → `prompt_agent` の `az grant-role` が不要に。
- ガードレール（CLAUDE.md）: 実デプロイはユーザーの明示指示があるときのみ。MVP 実装中はローカル（Docker DB＋
  既存 Foundry プロジェクト流用）で動作確認を進め、Azure への適用は指示を待つ。
</content>
