# Step 2 — バックエンド骨組み（FastAPI ＋ models ＋ エージェント CRUD）

Foundry **だけ**に依存する部分を先に通す。PostgreSQL はまだ繋がない（会話以外は DB 不要）。
ここまでで「モデル一覧が見える」「エージェントを作る/一覧/詳細/更新/削除できる」を curl で確認する。

> SDK の型・契約は [common-schema-api.md](./common-schema-api.md)、設定・認証は
> [common-architecture.md](./common-architecture.md) を参照。

---

## 目的

- FastAPI アプリの骨組み（CORS・ルーター登録・設定読み込み・Foundry クライアント生成）を立てる。
- `GET /api/models`（`deployments.list`）と **エージェント CRUD**（`/api/agents` 系）を実装。
- DB 非依存なので、Foundry の認証・ロール周りのトラブルをここで切り分けておく。

---

## 成果物（ファイル）

```text
backend/
├─ requirements.txt      # fastapi, uvicorn, azure-ai-projects>=2.2, azure-identity, openai, psycopg, python-dotenv
├─ .env.example          # step-1 で確定済みの雛形
└─ app/
   ├─ main.py            # FastAPI app・CORSMiddleware・router 登録（DDL は step-3 で追加）
   ├─ config.py          # env > .env > 既定 で設定読み込み（FOUNDRY_*, FRONTEND_ORIGIN, PG*）
   ├─ foundry.py         # AIProjectClient と get_openai_client() のラッパ（生成を一元化）
   └─ routers/
      ├─ models.py       # GET /api/models
      └─ agents.py       # /api/agents 系（GET/POST/GET{name}/PUT{name}/DELETE{name}）
```

---

## 設計メモ

### config.py

- 優先順位 **環境変数 > `.env` > 既定値**（CLAUDE.md）。`python-dotenv` で `.env` を読み、`os.environ` で上書きを許す。
- 公開する設定値：`foundry_project_endpoint` / `foundry_model_name` / `frontend_origin` / `pg_*`。
- 起動時に必須値（`FOUNDRY_PROJECT_ENDPOINT`）が無ければ明確に落とす（早期失敗）。

### foundry.py（クライアントのラッパ）

- `AIProjectClient(endpoint, credential=DefaultAzureCredential())` を **1 インスタンス共有**（アプリ寿命）。
- `get_openai_client()`（`project.get_openai_client()`）も同様に取得・共有。
- 目的：ルーターから SDK 生成の重複・資格情報の取り回しを排除し、`prompt_agent` の `_config.py` 相当の責務を担う。
- 例外は基本そのまま上げ、`main.py` の例外ハンドラで HTTP に変換（§エラー方針）。

### routers/models.py

- `GET /api/models` → `deployments.list(deployment_type="ModelDeployment")` を列挙し
  `[{ name, model_name, model_version, publisher }]` を返す（[common-schema-api.md](./common-schema-api.md) §3-1）。

### routers/agents.py（CRUD のマッピング）

| エンドポイント | 実装の要点 |
|---|---|
| `GET /api/agents` | `agents.list(kind="prompt")` を列挙し、各 `versions.latest.definition` から `{name, latest_version, model, instructions}` を組む（**N+1 不要**） |
| `POST /api/agents` | body `{name, model, instructions}` → `create_version(name, PromptAgentDefinition(model, instructions))` → `{name, version}` |
| `GET /api/agents/{name}` | `agents.get(name)`（必要なら `get_version`）で最新版の定義詳細 |
| `PUT /api/agents/{name}` | body `{model, instructions}` → `create_version(...)`（**新バージョン作成にマップ**） |
| `DELETE /api/agents/{name}` | `agents.delete(name, force=True)`（会話行の掃除は step-3 で DB が入ってから連結） |

- Pydantic でリクエスト/レスポンスのスキーマを定義（`AgentCreate`, `AgentSummary`, `AgentDetail` 等）。
- **PUT が状態を持たない**点を活かし、ハンドラは薄く保つ（更新＝新版作成）。

### main.py

- `CORSMiddleware` に `allow_origins=[config.frontend_origin]`、メソッド/ヘッダを許可。
- ルーター登録（`models`, `agents`）。`chat`（step-4）と DDL（step-3）は後続で追加する前提の空きを設けておく。
- 例外ハンドラ：Foundry の 401/403 は**透過**（体験シナリオのため）、その他は 500。

---

## 実装順（このステップ内）

1. `requirements.txt` → ルート `.venv` に追加インストール。
2. `config.py` → `foundry.py`（クライアント生成）→ `main.py`（最小起動）。
3. `routers/models.py`（最小の疎通確認に最適：読み取りのみ）。
4. `routers/agents.py`（C→R→詳細→U→D の順で足す）。

---

## 確認シナリオ（curl）

```text
GET  /api/models                                   → デプロイ済みモデルが返る（step-1 のモデル）
POST /api/agents {name, model, instructions}       → {name, version:1}
GET  /api/agents                                   → 作ったエージェントが latest_version 付きで一覧に出る
GET  /api/agents/{name}                            → model / instructions が見える
PUT  /api/agents/{name} {model, instructions(変更)} → version が 2 に上がる
DELETE /api/agents/{name}                          → 204、一覧から消える
```

- 体験：**自分の Foundry User ロールを `az` で剥奪 → 上記が 403 → 付け直すと通る**（認証と認可の分離）。
- 体験：**`PUT` で instructions を変える → `version` が上がる**（更新＝新版を体感。応答変化は step-4 で確認）。

---

## このステップの DoD

- [ ] `task backend` で uvicorn が :8000 で起動する
- [ ] `GET /api/models` が step-1 のモデルを返す
- [ ] エージェント CRUD が curl で一周する（作成→一覧→詳細→更新で version 増→削除）
- [ ] CORS が `FRONTEND_ORIGIN` に対して許可されている（step-5 の前提）
