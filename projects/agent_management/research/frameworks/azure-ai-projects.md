# azure-ai-projects（Foundry データプレーン SDK）— 蓄積ナレッジ

> このファイルは **Foundry SDK について「分かったこと」を貯める唯一の場所**。
> 実装前に必ずここを読み、新たに分かったことは**ここへ追記**する（再調査の防止）。
> **SDK は推測で実装しない**。`agents.*` / `responses.*` 等の正確な引数・戻り値は
> **必ずローカルコピー（samples / `docs/subclients.md`）で確認**する。

## 概要

- Microsoft Foundry プロジェクトのデータプレーンを叩く Python SDK（**ローカルにコピー済み**）。
  Entra ID 認証のみ（`DefaultAzureCredential`）。エンドポイントは
  `https://<account>.services.ai.azure.com/api/projects/<project>`。
- エージェント定義は `PromptAgentDefinition(model=..., instructions=...)`（MVP の対象）。

## ローカルコピー（＝正・最優先で読む）

SDK 本体のコピー: [`../../azure-ai-projects/`](../../azure-ai-projects/)

- 概要・認証・例: `azure-ai-projects/README.md`
- **全サブクライアント・全メソッド一覧**: `azure-ai-projects/docs/subclients.md`（API の地図として最優先）
- サンプル（実コード＝引数・戻り値の正本）: `azure-ai-projects/samples/`
  - `agents/sample_agent_basic.py` … 作成→会話→削除の最短ライン
  - `agents/sample_agent_stream_events.py` … **SSE ストリーミング**（`response.output_text.delta` 等のイベント型）
  - `agents/sample_external_agents_crud.py` … CRUD（create_version/get/list/delete）の型
  - `samples/responses/` … Responses API（ストリーミング含む）
  - `samples/deployments/` … モデルデプロイ列挙
  - `samples/connections/` … 接続列挙

## 本プロジェクトで使う主な操作

- **エージェント CRUD**: `agents.create_version` / `get` / `get_version` / `list` / `delete` / `delete_version`
- **モデル一覧**: `deployments.list()` / `deployments.get()`
- **チャット**: `get_openai_client()` で OpenAI 互換クライアントを得て
  `conversations.create()` → `responses.create(extra_body={"agent_reference": {...}})`（`stream=True` で SSE）

## 確認済みの事実（出典つき。新たに分かったら追記）

| # | 事実 | 出典 |
|---|---|---|
| A1 | エージェントは Foundry のリソース。名前＋バージョンで管理（`create_version`） | `samples/agents/sample_external_agents_crud.py`・`docs/subclients.md` |
| A2 | 会話・メッセージも Foundry が永続化。`conversations.create`＋`responses.create`。既定で **chat history を Cosmos DB に保存** | Tavily `agent_mgmt_research/0003`（baseline アーキテクチャ） |
| A3 | 履歴の読み戻しは `GET {endpoint}/openai/v1/conversations/{id}/items` | `docs/subclients.md`・[../decisions/02-architecture-review.md](../decisions/02-architecture-review.md) |
| A4 | **「あるエージェントに紐づく会話を一覧する」API は無い** → `conversation_id` はアプリが控える | Microsoft Q&A `agent_mgmt_research/0003` |
| A5 | 既定はサービス管理（Cosmos）。zero-data-retention 等が要れば client-managed（自前 DB）に倒す | Tavily `agent_mgmt_research/0003` |
| A6 | SDK は同期/非同期両対応。非同期は `azure.ai.projects.aio`＋`AsyncAzureOpenAI` 系。MVP は同期で十分 | `azure-ai-projects/azure/ai/projects/aio/`・[../decisions/02-architecture-review.md](../decisions/02-architecture-review.md) 3. |

## 参考 URL

- Agents overview: <https://learn.microsoft.com/azure/foundry/agents/overview>
- ランタイム（agents / conversations / responses の関係・`store` の挙動）:
  <https://learn.microsoft.com/azure/foundry/agents/concepts/runtime-components?tabs=python>
- baseline チャットアーキテクチャ（**履歴がどこに永続化されるか**の根拠）:
  <https://learn.microsoft.com/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-chat>
- 既存の手順書（このリポジトリ内）: `learn/foundry/prompt_agent/README.md`（CRUD・会話の呼び出し箇所が参考）

## 未調査・次に確認したいこと（TODO）

- [ ] `responses.create` の `agent_reference` の正確なキー構造（サンプルでフィールド名を最終確認）
- [ ] 会話アイテム取得のページング・並び順（`items` のレスポンス形）
- [ ] `delete` 時に Foundry 側の conversation も連動して消えるか（叩いて確認＝発展シナリオ）
