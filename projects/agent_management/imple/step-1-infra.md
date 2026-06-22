# Step 1 — インフラ（Bicep）＋ローカル Docker DB

以降すべての前提（Foundry endpoint・モデルデプロイ・PostgreSQL）を用意する。
正本の元ネタは `learn/foundry/prompt_agent/00_provision.py`（Foundry）と `learn/db/simple`（Postgres）を
**Bicep へ翻訳**する形。ローカル開発は Docker の PostgreSQL を使う。

> 共通前提は [common-architecture.md](./common-architecture.md)、リソースの使われ方は
> [common-schema-api.md](./common-schema-api.md) を参照。

---

## 目的

- Azure 側：Foundry 一式（AIServices アカウント＋プロジェクト＋モデルデプロイ）／PostgreSQL Flexible Server／
  **自分への Foundry User ロール割当**を Bicep で宣言的に作れる状態にする。
- ローカル側：`docker compose` で PostgreSQL を起動し、backend がすぐ繋げる状態にする。
- **ロール割当を IaC に内包**することで `prompt_agent` で必要だった `az` 手動 grant を不要にする。

---

## 成果物（ファイル）

```text
infra/
├─ main.bicep        # サブスクリプション/リソースグループスコープで modules を束ねる
├─ foundry.bicep     # AIServices アカウント(kind=AIServices)＋project＋モデルデプロイ
├─ postgres.bicep    # PostgreSQL Flexible Server ＋ 論理 DB
└─ roles.bicep       # ロール割当（自分の objectId へ Foundry User）
docker-compose.yml   # ローカル PostgreSQL（postgres:16）
Taskfile.yml         # db:up / infra:deploy 等（このステップで db:up と infra:deploy を用意）
```

---

## 設計メモ（モジュール分割と決めごと）

### main.bicep（オーケストレーション）

- 役割：パラメータ（location・prefix・モデル名・DB 管理者資格・自分の objectId 等）を受け、3 modules を呼ぶ。
- 出力：`FOUNDRY_PROJECT_ENDPOINT`・`PGHOST`・DB 名など、`.env` に書き戻す値を `output` する。
- スコープ：リソースグループ配下。ロール割当の対象スコープは Foundry プロジェクト（または account）に限定する。

### foundry.bicep

- AIServices アカウント `kind=AIServices`（`prompt_agent/00_provision.py` と同じ種別）。
- Foundry プロジェクト（account 配下の子リソース）。
- モデルデプロイ：既定 `gpt-4.1-mini`、`GlobalStandard` / `capacity=1`（従量・最小）。デプロイ名＝`FOUNDRY_MODEL_NAME`。
- 決めごと：**モデル名・SKU・capacity をパラメータ化**し、体験シナリオ（モデル差し替え）で変えやすくする。

### postgres.bicep

- Flexible Server v16 / Burstable B1ms / パスワード認証 / パブリックエンドポイント（`learn/db/simple` と同型）。
- 論理 DB（`agent_mgmt`）を子リソースで作成。
- **ファイアウォール規則は Bicep に書かない**（`learn/db/simple` の方針踏襲）。Task で出し入れし、
  「デフォルトで閉じている／許可制」を体感する余地を残す。

### roles.bicep

- 自分の objectId に対し **Foundry User（旧 Azure AI User）** ロールを Foundry スコープで割当。
- `roleDefinitionId` は組み込みロールの GUID を使う（環境非依存）。`principalId` はパラメータ（`az ad signed-in-user` 由来）。
- これにより step-2 以降の `DefaultAzureCredential` 呼び出しが 401/403 にならない。

### docker-compose.yml（ローカル）

- `postgres:16`、`POSTGRES_DB=agent_mgmt` / `POSTGRES_USER=app` / パスワードは `.env` の `PGPASSWORD`。
- ポート `5432:5432`、名前付きボリュームで永続化。backend の起動時 DDL（step-3）で十分なので init スクリプトは不要。

---

## 実装順（このステップ内）

1. `docker-compose.yml` ＋ Taskfile `db:up` を先に作る（**ローカルだけで step-2/3 を進められる**ようにする）。
2. `.env.example` の Postgres 既定値（[common-architecture.md](./common-architecture.md) §3）を確定。
3. Bicep を `postgres.bicep` → `foundry.bicep` → `roles.bicep` → `main.bicep` の順で書く（依存の浅い順）。
4. `Taskfile.yml` に `infra:deploy`（`az deployment group create -f infra/main.bicep`）を追加。

---

## 確認シナリオ

- **ローカル**：`task db:up` で PostgreSQL が起動し、`psql`（または `docker exec`）で `agent_mgmt` に接続できる。
- **Azure（明示指示があるときのみ）**：
  - `task infra:deploy` が成功し、`output` の `FOUNDRY_PROJECT_ENDPOINT` が得られる。
  - `az login` 済みで、SDK の `deployments.list()`（step-2 の `GET /api/models`）がモデルを 1 件以上返す。
  - 体験：**Foundry User ロールを `az role assignment delete` で剥がす → 呼び出しが 403 → 付け直すと通る**（step-2/4 で回収）。
  - 体験：**Postgres の FW 規則を出し入れ → 接続が通る⇄拒否**（`learn/db/simple` と同型）。

> ガードレール：実 deploy はユーザーの明示指示時のみ。指示が無ければローカル Docker＋既存 Foundry プロジェクト流用で先へ進む。

---

## このステップの DoD

- [ ] `task db:up` でローカル DB が起動し接続できる
- [ ] Bicep が 4 ファイルに分割され、`main.bicep` が必要な値を `output` する
- [ ] ロール割当が `roles.bicep` に入り、`az` 手動 grant が不要になっている（設計上）
- [ ] `.env.example` が確定し、`config.py`（step-2）が読む値が揃っている
