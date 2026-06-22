# 01 実装前に確定したい論点

実装に入る前に決めておくと手戻りが減る論点を、影響度の高い順に並べた。各項目に
**推奨**（学習目的・MVP に最も素直な選択）を付けたが、最終判断は実装時に行う。
背景・根拠は [02-architecture-review.md](./02-architecture-review.md) を参照。

---

## A. データの持ち方（最重要 / これだけは先に決める）

Foundry はエージェント定義・会話・メッセージ・実行履歴を **Foundry 側のマネージドストアに永続化する**
（既定は Cosmos DB）。つまり「DB」はすでに Foundry に存在する。ここで PostgreSQL に何を持たせるかが
本プロジェクト全体の自然さを左右する。詳細は [02](./02-architecture-review.md) の「データモデルの所在」。

- **A-1. エージェント定義の正本（source of truth）はどちらか**
  - 選択肢: (a) Foundry が正本・Postgres は持たない / (b) Postgres が正本で Foundry に同期 / (c) 二重持ち
  - **推奨: (a)**。`agents.create_version` 等で Foundry が名前＋バージョン管理する。Postgres に定義を複製すると
    同期ずれの管理という本質的でない仕事が増える。
- **A-2. では PostgreSQL は何を保存するのか**（これを言語化できないと PostgreSQL 採用が宙に浮く）
  - **推奨**: Foundry が **クエリさせてくれない app 固有メタデータ**だけを持つ。具体的には
    **「どのエージェントにどの会話（conversation_id）がぶら下がるか」のインデックス**（会話一覧・タイトル・作成時刻・
    作成者）。Foundry には「このエージェントの会話を一覧する」API が見当たらず、`conversation_id` は
    アプリが控えておく必要があるため、ここは Postgres の自然な仕事になる。
  - 併せて持つ候補: 表示用エイリアス、タグ、論理削除フラグ、お気に入り順。
- **A-3. チャット履歴（メッセージ本文）を Postgres にも持つか**
  - **推奨: 持たない（MVP）**。本文は Foundry の conversation が正本。表示時は
    `GET /openai/v1/conversations/{id}/items` で取得。二重保存は zero-data-retention 等の要件が出てから。

> この A をどう決めても「PostgreSQL を Docker / Azure で動かす」学習価値は残せる（会話インデックス＝
> 立派なリレーショナルデータ）。ただし**「DB が主役の CRUD」ではなく「Foundry の薄いインデックス」**になる、
> という性格の違いだけは最初に合意しておきたい。

---

## B. チャットのストリーミング方式（Cycle.js と直結する論点）

SDK はトークンを **SSE（`stream=True` で `response.output_text.delta` イベント列）** で返せる
（`azure-ai-projects/samples/agents/sample_agent_stream_events.py` 参照）。一方 Cycle.js の標準
`@cycle/http` ドライバは **一発のリクエスト/レスポンス型**で、SSE / `EventSource` を素直には扱えない。

- **B-1. MVP でストリーミングするか**
  - 選択肢: (a) 非ストリーミング（1 リクエスト＝1 完成レスポンス）でまず通す / (b) 最初からストリーミング
  - **推奨: (a) で骨組みを通し、(b) は「Cycle.js ドライバ自作」の学習回として独立させる**。
    理由は B-2。
- **B-2. ストリーミングを Cycle.js でどう実現するか**（採用するなら）
  - 選択肢: (a) `EventSource` をラップした**カスタムドライバを自作** / (b) `fetch` のストリーム読みを
    ドライバ化 / (c) 諦めて非ストリーミング
  - **推奨: (a)**。ドライバ自作は Cycle.js の中核概念そのもの（[frameworks/cyclejs.md](../frameworks/cyclejs.md) 参照）で、
    「副作用＝ドライバ」という思想を体験する最良の題材。`@cycle/http` を無理に使うより自然。
  - 注意: SSE は単方向・UTF-8 テキストのみ・HTTP/1.1 ではドメインあたり 6 接続上限。チャット 1 本なら問題なし。
- **B-3. バックエンドの SSE 中継**: FastAPI 側は `StreamingResponse`（`media_type="text/event-stream"`）か
  `sse-starlette` / FastAPI の `EventSourceResponse` で SDK のイベントを中継する。**推奨: まず素の
  `StreamingResponse` で十分**。

---

## C. リソース構築（IaC）の方式

README は「リソース構築は IaC で行う」と宣言。`learn/foundry/prompt_agent` は Python 管理 SDK で
構築していたが、本プロジェクトは IaC。

- **C-1. IaC は Bicep か Terraform か**
  - **推奨: Bicep**（このリポジトリの Azure リソース構築の主流。auth/network/vm/db/k8s が Bicep）。
- **C-2. ロール割当を IaC に含めるか**
  - `prompt_agent` では「mgmt SDK がロール割当 API を持たず `az` 頼り」だった。**Bicep なら
    `Microsoft.Authorization/roleAssignments` をネイティブに書ける**ので、ここは IaC 化が素直
    （自分への Foundry User ロール付与まで Bicep に載せられる）。**推奨: Bicep に含める**。
- **C-3. Bicep で作る範囲**: AIServices アカウント（kind=AIServices）＋ Foundry プロジェクト＋モデルデプロイ
  （AOAI、既定 `gpt-4.1-mini` 等）＋ PostgreSQL Flexible Server ＋ 必要なロール割当。
  既存 `learn/db/simple` の Postgres Bicep、`learn/foundry/prompt_agent/00_provision.py` のリソース定義が下敷きになる。

---

## D. 認証・マルチユーザー

- **D-1. アプリ利用者の認証**
  - **推奨: MVP は認証なし（ローカル単一利用者）**。バックエンドは `DefaultAzureCredential`（`az login`）で
    Foundry を叩く。A-2 の「作成者」列は将来の布石として持つだけ。
  - 発展: auth トピックの蓄積（MSAL.js + Entra）を後段で接続すると学習がつながる。
- **D-2. バックエンド→Foundry の認証**: `DefaultAzureCredential`。ローカルは `az login`、
  Azure 上は Managed Identity（k8s/container トピックでキーレス pull を学んだのと同型）。**推奨: この方針**。
- **D-3. バックエンド→PostgreSQL の認証**: パスワード or Entra 認証パスワードレス。
  **推奨: MVP はパスワード（`learn/db/simple` と同型）**、Entra 認証は発展課題（k8s/workload-identity で既習）。

---

## E. アプリの形・配置

- **E-1. フロントの配信方法**: Cycle.js を (a) 静的ビルドして FastAPI から配信 / (b) 別オリジンで dev サーバー。
  **推奨: ローカルは (b)（Vite 等の dev サーバー）＋ CORS、本番相当は (a) を検討**。
- **E-2. ローカル実行のオーケストレーション**: PostgreSQL は Docker、バックエンドは uvicorn、フロントは dev サーバー。
  3 つ起動するので **justfile では厳しく Taskfile（CLAUDE.md の指針どおり）** が妥当。**推奨: Taskfile**。
- **E-3. Cycle.js のビルドツールチェーン**: ローカルコピーは古い（TS 3.2.4 / RxJS 6 / Node 8 想定）。
  アプリ側は**最新の `@cycle/run` / `@cycle/dom` / `xstream` を npm で入れ、Vite でバンドル**するのが素直。
  ローカルコピーは「ドキュメント・サンプル参照用」と割り切る。**推奨: アプリ依存は最新を別途取得**。

---

## F. スコープ確認（MVP の線引き）

README の MVP を実装観点で具体化したもの。ここを合意しておくと「どこまで作るか」がぶれない。

- 対象は **AOAI モデル**かつ **prompt agent のみ**、**ツール非対応**（README どおり）。
- モデルは**デプロイ済みのものを選ぶだけ** → `deployments.list()` で一覧取得して選択肢にする
  （`azure-ai-projects/docs/subclients.md` の `.deployments.list`）。
- エージェント CRUD = `agents.create_version` / `get` / `list` / `delete`（バージョン概念をどう UI に出すかは G）。
- チャット = `conversations.create` → `responses.create(agent_reference=...)`。

- **F-1. エージェントの「更新（U）」をバージョンとして見せるか**
  - Foundry は更新＝新バージョン作成（`create_version`）。**推奨: MVP は「最新バージョンだけ」を見せ、
    更新は内部的に新バージョン作成にマップ**。バージョン履歴の閲覧は発展課題。
- **F-2. 削除（D）の意味**: `agents.delete`（エージェントごと）か `delete_version`（版だけ）か。
  **推奨: MVP は「エージェントごと削除」= `agents.delete`**。

---

## まとめ：先に決める 3 つ

1. **A-2: PostgreSQL の役割＝「エージェント↔会話インデックス」**だと合意する（プロジェクトの性格が決まる）。
2. **B-1/B-2: ストリーミングは後回し、やるならドライバ自作**という段取りにする。
3. **C-1/C-2: Bicep でロール割当まで IaC 化**する（`prompt_agent` の `az` 依存を解消できる）。
</content>
