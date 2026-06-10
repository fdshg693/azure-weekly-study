# 学習トピック一覧（ユーザーの Azure レベル把握用）

このリポジトリは Azure を**トピックごとにサブフォルダで分け、各プロジェクトでコードを通して**
段階的に学ぶ構成。各トピックの詳細・概念の習得状況は `learn/{topic}/CLAUDE.md` に書く
（ここはトピック横断の短い概要に留める）。
共通方針は「**まず一般概念／最小構成 → 実装 → 設定を出し入れして因果を確かめる**」「**構築・実行は
ユーザー自身が行い、AI は Azure 上で実行しない**」。

> 注記: 各トピックの概要は代表プロジェクトを中心に**抜粋**している。全プロジェクトの網羅は
> 各 `learn/{topic}/CLAUDE.md` を参照。

## auth — 認証・認可（最も深く進んでいる領域）

`./auth`（詳細: [auth/CLAUDE.md](./auth/CLAUDE.md)、計画: [auth/PLAN.md](./auth/PLAN.md)）
技術: Bicep / just(Taskfile) / Azure CLI、必要に応じてフロント（バニラ JS + MSAL.js）。

OAuth 2.0 / OpenID Connect を土台に Entra ID を学ぶ。`entra-spa-login`（SPA で認証の最小ループ・
ID/アクセストークンの違い・PKCE）→ `api-protect`（自前リソースサーバー・JWT 検証・401/403）→
`app-roles-rbac`（App ロール・`scp` と `roles` の違い・クレームベース認可）→ `confidential-web`
（コンフィデンシャルクライアント・client_secret・BFF）と、**認証→認可、パブリック→コンフィデンシャル**へ
段階的に深化済み。

## func — Azure Functions

`./func`（詳細: [func/CLAUDE.md](./func/CLAUDE.md)）
技術: Terraform / Python v2 / Functions Core Tools。

`blob_logger`（Blob トリガー × 出力バインディングだけで入出力／ポーリング遅延／無限ループ回避）と
`func_keyvault`（Managed Identity × Key Vault × RBAC スコープを App 単位で分離、Reader/Writer、
auth level）。サーバーレスのトリガー／バインディングと、Functions から他リソースへの安全なアクセスを学習。
Event Grid トリガー化・キーレス化は未着手。

## storage — Azure Storage

`./storage`（詳細: [storage/CLAUDE.md](./storage/CLAUDE.md)）
技術: Terraform / just / Azure CLI。

`simple`（静的 Web サイトで `$web` だけ公開、公開フラグと SAS で「他は公開されない」を担保）と
`private_endpoint`（VNet + Private Endpoint + Private DNS Zone で閉域化、VM から内部到達／外部拒否を対比）。
**公開経路上の範囲制御**と**ネットワーク的閉域化**の 2 つの守り方を学習。

## network — ネットワーク

`./network`（詳細: [network/CLAUDE.md](./network/CLAUDE.md)）
技術: Bicep / just / Azure CLI。

`basic`（Azure での基本的なネットワーク構築＋通信一般）、`advanced`（より高度な内容）、
`memo`（ローカルでコマンドを叩く学習メモ、Git 管理外・指示なしでは触らない）。

## foundry — Azure AI Foundry（Agent Service）

`./foundry`（詳細: [foundry/CLAUDE.md](./foundry/CLAUDE.md)）
技術: Python（mgmt SDK / `azure-ai-projects` / Agent Framework）/ just。

`prompt_agent`（エージェント定義を Foundry 側に作り、リソース作成〜会話までほぼ Python で一周）、
`ephemeral_agent`（定義をコード内に持つエフェメラル、ツールの実行場所＝サーバー vs ローカルの違い）、
`hosted_agent`（ホステッドの入口、サンプル取得のみで自作デプロイは未着手）。
コントロール／データプレーンの 2 層、Foundry のロールとモデルデプロイ課金感覚を学習。
