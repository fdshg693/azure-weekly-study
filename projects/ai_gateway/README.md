# AI Gateway

## 概要

Azure上にAI GATEWAYおよび、管理UIを構築するプロジェクトです。

設計の全体像・実装ステップ・注意点は [PLAN.md](PLAN.md) を参照。

## 現在の機能

- **ステップ0: IaC 土台**（[PLAN.md](PLAN.md) §4 ステップ0）
    - Terraform で Azure OpenAI（Cognitive Services / kind=OpenAI）アカウント本体を作成
    - 実行者（自分）へ RBAC ロールを付与（管理: Cognitive Services Contributor / 推論: Cognitive Services OpenAI User）
    - モデルデプロイは敢えて作らない（後続ステップで「管理画面から作る対象」として残す）
    - キーレス（`local_auth_enabled=false`）を既定とし、Entra ID / Managed Identity 認証で統一
- **ステップ1: データプレーン推論の最小エンドポイント**（[PLAN.md](PLAN.md) §4 ステップ1）
    - `app/` に Node.js + Express の最小アプリ。`POST /infer` で推論を 1 発通す
    - `openai` SDK の `AzureOpenAI` クライアントを **デプロイ名** で生成し、Responses API で呼ぶ
    - 認証は **Managed Identity / `DefaultAzureCredential`**（API キー不要・キーレス）
    - 勘所:「モデル名ではなくデプロイ名で呼ぶ」「認証は Entra ID トークン」を押さえる
- **ステップ2: コントロールプレーン読み取り API**（[PLAN.md](PLAN.md) §4 ステップ2）
    - `GET /deployments`（作成済みデプロイ一覧）/ `GET /models`（デプロイ可能なベースモデル一覧）を追加
    - 実体は [app/arm-client.js](app/arm-client.js)。SDK を使わず **生の ARM REST** を `fetch` で叩く
    - データプレーンとの「3つの違い」を体験: 認証スコープ（`management.azure.com`）・API バージョン（ARM GA `2025-06-01`）・必要ロール（Contributor 相当）がいずれも推論とは別物
    - 読み取り専用なのでガードレール上も安全
- **ステップ3: コントロールプレーン書き込み API**（[PLAN.md](PLAN.md) §4 ステップ3）
    - `POST /deployments`（モデル名・バージョン・SKU・容量(TPM)を指定して作成/更新）/ `DELETE /deployments/:name`（削除）を追加
    - ARM の PUT/DELETE は長時間処理(LRO)。作成直後は state が `Accepted`/`Creating` で、`Succeeded` になるまで `GET /deployments` でポーリングして確認する
    - 作成→一覧反映→削除のライフサイクルをアプリ経由で体験。実リソースを変更するため要 Contributor ロール

## 今後の予定

- 様々なAIモデルを管理画面から簡単にデプロイ（コントロールプレーン）← ステップ2で「一覧（読み取り）」、ステップ3で「作成/削除（書き込み）」を実装済み。残るは管理 UI（画面）統合
- デプロイしたAIモデルをAPI経由で呼び出し可能（データプレーン）← ステップ1で最小版を実装済み

## セットアップ（ステップ0）

前提: `az login` 済み・Terraform / just インストール済み。
実リソースを作成するため、[CLAUDE.md](../../CLAUDE.md) のガードレールに従い、実行はユーザーの判断で行う。

```pwsh
just init        # terraform init
just plan        # 変更プレビュー（何が作られるか確認）
just apply       # リソース作成（RG + Azure OpenAI アカウント + ロール）
just verify      # アカウント / デプロイ0件 / ロール割り当てを確認
just models      # このリージョンでデプロイ可能なモデル一覧
just env-sync    # terraform output から .env を生成（後続ステップ用）
just destroy     # 後片付け
```

> ロール付与（`assign_roles_to_current_user`）にはサブスクリプションの Owner / User Access Administrator 権限が必要。
> 権限が無い場合は `variables.tf` で `false` にして、別途手動でロールを付与する。

## セットアップ（ステップ1：データプレーン推論）

前提:
- ステップ0 のリソースが作成済み（`just apply`）で、推論ロール（Cognitive Services OpenAI User）が自分に付与されていること。
- **手動で 1 つだけモデルをデプロイ**しておくこと（このステップではまだ管理 UI を作らないため）。
  Responses API 対応モデル（GPT-4.1 / GPT-5 等）を使う。`just` で簡単に行える:
  ```pwsh
  just models           # このリージョンの可用モデル/バージョン/SKU を確認
  just deploy-model     # 既定（GPT-4.1 / GlobalStandard / TPM 10）でデプロイ
  # 別モデル例: just deploy-model gpt-5 gpt-5 2025-08-07
  just deploy-list      # 作成済みデプロイと状態(succeeded等)を確認
  ```
  > これらの操作には Contributor ロール（管理＝コントロールプレーン書き込み）が要る。
  > 本来ステップ3 で管理 UI から行う対象だが、それまでの動作確認用に CLI ラッパーを用意している。

実行:

```pwsh
just app-install     # 依存パッケージをインストール
just app-env-sync    # terraform output から app/.env を生成（endpoint + 既定 deployment）
just app-dev         # アプリ起動（要 az login。既定ポート 3000）

# 別ターミナルで推論を 1 発投げる（デプロイ名は省略時 app/.env の既定）
just infer "日本の首都は？"
just infer "こんにちは" gpt-5     # 第2引数でデプロイ名を上書き
```

> `app/env-sync` は既定デプロイ名を `gpt-4.1` にする。別名でデプロイした場合は
> 環境変数 `AOAI_DEPLOYMENT` を設定して `just app-env-sync` するか、`app/.env` を直接編集する。

### 叩いて挙動が変わることを体験（[PLAN.md](PLAN.md) §4 ステップ5 の先取り）

- 存在しないデプロイ名で呼ぶ → `just infer "test" no-such-deploy` で **404** を観測。
- 推論ロールを外す（`az role assignment delete ...`）→ **401/403** を観測（権限伝播に時間差あり）。
- 後片付け → `just deploy-delete gpt-4.1` でデプロイを削除（`just deploy-list` で消えたことを確認）。

## セットアップ（ステップ2：コントロールプレーン読み取り）

前提:
- ステップ0 のリソースが作成済みで、**管理ロール（Cognitive Services Contributor）**が自分に付与されていること。
  - 注意: 推論ロール（OpenAI User）だけでは一覧取得が **403** になる。これはステップ5 で体験する分離の肝。
- `just app-env-sync` を実行して `app/.env` に `AZURE_OPENAI_ACCOUNT_ID`（ARM のフルリソース ID）が書き出されていること。

実行:

```pwsh
just app-env-sync    # endpoint + account-id + 既定 deployment を app/.env に書き出し
just app-dev         # アプリ起動（要 az login。既定ポート 3000）

# 別ターミナルで読み取り API を叩く（アプリの ARM プロキシ経由）
just gw-deployments  # GET /deployments … 作成済みデプロイ一覧
just gw-models       # GET /models … このリージョンでデプロイ可能なベースモデル一覧
```

> `just deploy-list` / `just models`（az CLI 直叩き）と同じ情報を、**アプリ経由（コントロールプレーン REST プロキシ）**で取得する。
> データプレーン（`/infer`）とは認証スコープ・API バージョン・必要ロールが別物である点を、同じアプリ内で見比べられる。

### 叩いて挙動が変わることを体験（ステップ2 版）

- 管理ロールを外す（`az role assignment delete --role "Cognitive Services Contributor" ...`）→ `just gw-deployments` が **403** に。一方 `just infer` は通る → 2 面のロール分離を体感。
- `just deploy-model` で 1 つ作る → `just gw-deployments` に現れる。`just deploy-delete` で消す → 一覧から消える。

## セットアップ（ステップ3：コントロールプレーン書き込み）

前提:
- ステップ2 と同じ（**Cognitive Services Contributor** ロール + `app/.env` の `AZURE_OPENAI_ACCOUNT_ID`）。
- ステップ0〜2 までの CLI ラッパー（`just deploy-model` 等）と違い、**作成/削除もアプリ経由（ARM プロキシ）**で行う。

実行（アプリ起動中・別ターミナルで）:

```pwsh
# 作成（既定: GPT-4.1 / GlobalStandard / TPM 10）。別モデルは引数で上書き
just gw-deploy-create                                  # POST /deployments
just gw-deploy-create gpt-5 gpt-5 2025-08-07           # 例: GPT-5 を作る

# 作成は時間がかかる。state が Succeeded になるまで一覧でポーリング確認
just gw-deployments                                    # state: Accepted/Creating → Succeeded

# できたデプロイをその場で推論（データプレーン）
just infer "日本の首都は？"

# 後片付け
just gw-deploy-delete gpt-4.1                           # DELETE /deployments/gpt-4.1
```

> `az` CLI 直叩き（`just deploy-model` / `just deploy-delete`）と同じ操作を、アプリの **書き込み API（PUT/DELETE プロキシ）** 経由で行う。
> これで「作成→一覧反映→推論→削除」の一連のライフサイクルがアプリだけで完結する（残るは画面統合＝ステップ4）。

### 叩いて挙動が変わることを体験（ステップ3 版）

- 容量(TPM)をクォータ上限より大きく指定して作成 → ARM が **4xx** を返すのを観測（`just gw-deploy-create gpt-4.1 gpt-4.1 2025-04-14 GlobalStandard 100000`）。
- 存在しないデプロイ名を削除 → **404** を観測（`just gw-deploy-delete no-such-deploy`）。
- 管理ロールを外した状態で作成/削除 → **403**（一方、推論は OpenAI User があれば通る）。

##　将来機能

- Azure以外の外部プロバイダなどもサポート
- APIキー管理を行う
- カスタムエンドポイントによる、柔軟なAIモデルの呼び出し
- ログ・コストの管理