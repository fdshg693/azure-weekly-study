# 02 アーキテクチャ妥当性レビュー

選んだスタック（Cycle.js / FastAPI / PostgreSQL / Foundry SDK）を、学習目的を尊重しつつ
「不自然・無理がある箇所」と「より素直な代替」の観点でレビューする。
**結論を先に言うと、スタック自体は学習教材として妥当。唯一きちんと言語化が要るのは PostgreSQL の役割**。

---

## 1. データモデルの所在 ── 最大の論点

### 事実（ローカルサンプル＋公式から確認）

- **エージェントは Foundry のリソース**。`agents.create_version(agent_name, definition=PromptAgentDefinition(...))`
  で作成され、**名前＋バージョン**で管理。`get` / `list` / `delete` / `delete_version` が揃う
  （`azure-ai-projects/samples/agents/sample_external_agents_crud.py`, `docs/subclients.md`）。
- **会話・メッセージも Foundry が永続化**。`conversations.create` でスレッドを作り、`responses.create` が
  応答を会話に追記する。公式の baseline アーキテクチャは「service-managed conversations が
  **chat history を Cosmos DB に永続化**する」と明記（Tavily 調査 0003）。
- 履歴は `GET {endpoint}/openai/v1/conversations/{conversation_id}/items` で読み戻す。
  ただし**「あるエージェントに紐づく会話を一覧する」API は見当たらない** → `conversation_id` は
  呼び出し側が控える必要がある（Microsoft Q&A 0003）。

### 何が不自然になりうるか

「CRUD アプリ＋PostgreSQL」と聞くと、普通は **DB がエージェント定義やチャット履歴の正本**を持つ絵を描く。
しかし本件では Foundry がすでにその正本を持つ。素朴に Postgres へ定義や履歴を複製すると、
**Foundry と DB の二重管理・同期ずれ**という、学習の本筋（Foundry Agent の操作）から外れた仕事が増える。
これは典型的な「無理のある実装」。

### 素直な設計（推奨）

PostgreSQL には **Foundry が問い合わせさせてくれない app 固有の情報だけ**を持たせる。

| データ | 正本 | Postgres に持つ？ |
|---|---|---|
| エージェント定義（model / instructions / version） | **Foundry** | ✗（必要時 `agents.get`） |
| メッセージ本文・実行履歴 | **Foundry**（既定 Cosmos） | ✗（必要時 conversation items を取得） |
| エージェント↔会話のひも付け（会話一覧／タイトル／作成時刻／作成者） | **アプリ** | **✓ ここが主役** |
| 表示用エイリアス・タグ・論理削除・並び順 | アプリ | ✓（任意） |

この切り分けなら、PostgreSQL は「Foundry の薄いインデックス／アプリ固有メタストア」という
**明確で正当な役割**を得る。リレーショナル DB の学習価値（テーブル設計・外部キー・一覧クエリ）も十分残る。

> 公式の baseline は「既定はサービス管理（Cosmos）、ただし zero-data-retention・独自のコンテキスト圧縮・
> 複数チャネルで独立したセッション管理が要るなら **client-managed**（自前 DB）に倒す」と整理している。
> 本プロジェクトは学習目的なので **既定（サービス管理）＋薄い自前インデックス**が最も素直。
> 「あえて client-managed で履歴も Postgres に持つ」を学習テーマに**選ぶ**のは可。ただしそれは
> MVP ではなく明示的な発展課題として切り出すべき（[01](./01-open-decisions.md) A-3）。

---

## 2. フロントエンド：Cycle.js

### 妥当性

- **学習教材としては妥当**。FRP（ストリーム中心）と「副作用＝ドライバ」という独特のモデルは、
  React/Vue とは違う発想を強制してくれるので学びになる。README が「あえて採用」と書くとおりの位置づけ。
- **ただしエコシステムは成熟・停滞気味**。Tavily 調査（0001）でも 2025 のフレームワーク動向で
  ほぼ言及されず、ローカルコピーの本体も古い（TS 3.2.4 / RxJS 6 / Node 8 想定）。
  → **「枯れていて情報が少ない」前提で、公式ドキュメントとローカルサンプルを正とする**運用が必須。
  これは README の方針（逐一ドキュメント確認）と一致しているので問題ない。

### 不自然になりうる箇所と代替

- **チャットのストリーミング（SSE）と `@cycle/http` の相性が悪い**。標準 HTTP ドライバは一発応答型で、
  トークンを逐次受けるのに向かない。
  - **素直な代替**: `EventSource`（または `fetch` のストリーム）を **カスタムドライバ化**する。
    ドライバ自作は Cycle.js の核心概念なので、むしろ学習価値が高い。MVP は非ストリーミングで通し、
    ストリーミングは独立した回として扱う（[01](./01-open-decisions.md) B）。
- **CRUD フォームの状態管理**。素の `xstream.fold` でも書けるが、フォーム・一覧・選択など状態が増えると辛い。
  - **素直な代替**: `@cycle/state`（onionify）でコンポーネント分割＋状態の合成を使う
    （ローカル: `cyclejs/docs/content/api/state.md`）。最初からこれを土台にすると素直。

> ここは「Cycle.js を捨てる」提案ではない（学習目的を尊重）。**Cycle.js の流儀（ドライバ／state）に
> 寄せれば不自然さは解消できる**、というのがレビュー結論。

---

## 3. バックエンド：FastAPI ＋ azure-ai-projects SDK

- **素直で相性が良い**。SDK が同期/非同期両対応、SSE ストリーミングも `stream=True` で素直に出せる
  （`samples/agents/sample_agent_stream_events.py`）。FastAPI 側は `StreamingResponse` で中継するだけ
  （Tavily 0004 で定番パターンを確認）。
- 注意点（実装メモ）:
  - SDK の同期クライアントを使うなら、ストリーミング中継はジェネレータ＋`StreamingResponse`。
    非同期で書くなら `azure.ai.projects.aio` ＋ `aiohttp`、`AsyncAzureOpenAI` 系。**MVP は同期で十分**。
  - モデル一覧は `deployments.list()`、エージェント CRUD は `agents.*`、会話は `get_openai_client()` 経由。
  - 「REST を直接叩かず SDK を最大限使う」という README の方針は、上記 API が揃っているので無理なく守れる。

---

## 4. データベース：PostgreSQL

- **役割さえ 1.（A-2）で確定すれば妥当**。会話インデックス＋アプリメタデータというリレーショナルな対象がある。
- ローカル Docker / Azure Flexible Server の二面運用は `learn/db/simple` で既習なので素直に踏襲できる。
- 不自然になるのは「Foundry にある履歴を丸ごと Postgres にも持つ」ことだけ。そこを避ければ問題なし。

---

## 5. 全体構成（推奨像）

```text
[Cycle.js SPA]
  │  REST(JSON)         … エージェント CRUD / 会話一覧 / メッセージ送信
  │  SSE(text/event-stream) … チャットのトークン逐次（発展。ドライバ自作）
  ▼
[FastAPI backend]  ── DefaultAzureCredential ──►  [Foundry Agent Service]
  │                                                 ├ agents (定義・バージョン) ＝正本
  │                                                 └ conversations / responses (履歴) ＝正本(既定Cosmos)
  └─ psycopg ──►  [PostgreSQL]
                    └ エージェント↔会話インデックス＋アプリメタdata ＝アプリ固有の正本
```

- IaC（Bicep）で **AIServices＋Foundry プロジェクト＋モデルデプロイ＋PostgreSQL＋ロール割当**を構築。
- ロール割当を Bicep に載せられるので、`prompt_agent` で `az` に逃がしていた箇所が IaC で閉じる（学習上の前進）。

---

## 6. レビュー総括

| 項目 | 判定 | コメント |
|---|---|---|
| Cycle.js（フロント） | 採用可（学習価値あり） | 情報少・古いのは前提。ドライバ／state の流儀に寄せれば不自然さは消える |
| FastAPI＋SDK（バック） | 素直 | SSE 中継まで定番どおり。REST 直叩き回避も無理なく満たせる |
| PostgreSQL | 役割の言語化が条件 | 「会話インデックス＋メタ」に限定。履歴の二重持ちは避ける（やるなら発展課題） |
| IaC=Bicep | 素直＆前進 | ロール割当まで IaC 化でき、`prompt_agent` の `az` 依存を解消 |
| ストリーミング | MVP 後回し推奨 | やるなら `EventSource` のカスタムドライバ。`@cycle/http` 直は不自然 |

**唯一の必須アクション**は「PostgreSQL の役割を A-2 のように確定すること」。ここさえ決めれば、
他は学習教材として自然に成立する。
</content>
