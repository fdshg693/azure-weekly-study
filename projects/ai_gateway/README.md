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

## 今後の予定

- 様々なAIモデルを管理画面から簡単にデプロイ（コントロールプレーン）
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

##　将来機能

- Azure以外の外部プロバイダなどもサポート
- APIキー管理を行う
- カスタムエンドポイントによる、柔軟なAIモデルの呼び出し
- ログ・コストの管理