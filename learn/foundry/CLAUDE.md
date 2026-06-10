# Azure AI Foundry の学習

Azure AI Foundry（旧 Azure AI Studio）の **Agent Service** を中心に、エージェントの作り方・
呼び出し方・ツールの与え方を、プロジェクトごとにサブフォルダで分割して学ぶ。
各プロジェクトは公式クイックスタートを元ネタにしつつ、「**できる限り Python だけで一周する**」
方針で、コントロールプレーン（リソース作成）からデータプレーン（会話）までを通す。

- `./README.md`：公式ドキュメントへのリンク集（Agent Service / Runtime / ツールカタログ）

## 使用技術

- 言語は **Python**（auth は Bicep、func は Terraform 中心だったのに対し、foundry はコード主体）。
  - 仮想環境は各プロジェクトの `.venv`、依存は `requirements.txt`、コマンドは `justfile` でレシピ化。
  - 認証は `az login` 済みの資格情報を `AzureCliCredential` / `DefaultAzureCredential` が使う。
- SDK はパターンによって使い分ける:
  - コントロールプレーン（リソース／プロジェクト／モデルデプロイ作成）: `azure-mgmt-cognitiveservices`
  - データプレーン（エージェント作成・会話）: `azure-ai-projects` 2.x + `openai`
  - エフェメラル: **Agent Framework**（`agent-framework-foundry`）
- 接続情報は `.env` / 環境変数 / `config.json` で注入（優先順位は **環境変数 > `.env` > 既定値**）。

## プロジェクト一覧

### prompt_agent

`./prompt_agent`

**プロンプトエージェント**（エージェント定義を Foundry 側のリソースとして作る）を、
**リソース作成から会話まで「ほぼ Python だけ」で一周**するハンズオン。
`00_provision.py` で account(kind=AIServices)＋project＋モデルデプロイを管理 SDK で作り `config.json` を生成、
`01_create_agent.py` で `agents.create_version` ＋ `PromptAgentDefinition` でエージェントを作成、
`02_chat.py` で conversation を作り 2 ターン会話して**履歴維持**を確認、`99_cleanup.py` で後片付け。
学習の肝は **コントロールプレーン（mgmt SDK）とデータプレーン（projects SDK）の 2 層**を意識すること、
**ロール割当だけは Python SDK が API を持たず `az`（Foundry User ロール）に頼る**こと、
モデルデプロイは GlobalStandard / capacity=1 の従量課金で放置せず消す、という運用感覚。

### ephemeral_agent

`./ephemeral_agent`

**エフェメラルエージェント**（エージェント定義＝instructions / tools / model を Foundry 側ではなく
**アプリのコード内**に持つ）パターンを学ぶ。`create_version` で作成・削除せず、毎回コードから
組み立てて Responses API を呼ぶのでライフサイクル管理が不要。SDK は **Agent Framework**。
リソースは作らず、`prompt_agent` で作った Foundry プロジェクト＋モデルデプロイを `.env` で**流用**する。
2 種類のツールの**実行場所の違い**を体験するのが本題:**Web 検索ツール（`get_web_search_tool()`）は
サーバーサイド（Foundry）実行でローカル実装不要**、**カスタムツール（`@tool` を付けた普通の Python 関数）は
ローカル実行**。`01`（カスタムのみ）→`02`（Web 検索のみ）→`03`（両方）の順で確かめる。

### hosted_agent

`./hosted_agent`

**ホステッドエージェント**（コード／コンテナを Foundry 上にデプロイして動かす）の入口。
現状は公式サンプルを GitHub から取得してデプロイ方法をなぞる段階で、`samples/` にサンプルをコピー済み。
azd ベースのデプロイとソースコードからのデプロイの 2 経路がドキュメントに紐づく（README 参照）。
**自作コードでの本格的なハンズオンは未実施**（このトピックで最も踏み込めていない領域）。

## 学習した概念

- Agent Service の 3 つのパターン（プロンプト / エフェメラル / ホステッド）の違いと使い分け
- コントロールプレーン（mgmt SDK）とデータプレーン（projects SDK）の 2 層構造
- プロンプトエージェントの作成（`create_version` + `PromptAgentDefinition`）と conversation での履歴維持
- エフェメラルエージェント（定義をコード内に持つ）と Agent Framework
- ツールの実行場所の違い（ホスト型 Web 検索＝サーバーサイド／カスタム関数＝ローカル）と `@tool` 定義
- Foundry プロジェクト／モデルデプロイの作成・流用、`config.json` / `.env` による接続情報の受け渡し
- Foundry のロール（Foundry User / Account Owner）と、ロール割当が `az` 頼りになる事情
- モデルデプロイの課金（GlobalStandard / 従量）とクリーンアップの重要性

## まだ学習できていない概念（次プロジェクトの候補）

- **ホステッドエージェントの自作コードデプロイ**（azd / ソースコードからの本格運用）
- ツールカタログの他のツール（Code Interpreter、ファイル検索、各種コネクタ等）
- 複数エージェントのオーケストレーション / ハンドオフ
- 評価（evaluation）・トレーシング・監視と本番運用
- RAG（自前データの取り込み・グラウンディング）
- ロール割当を含めた「完全に Python だけ」での自動化（`azure-mgmt-authorization`）
