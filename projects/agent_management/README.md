# agent_management — Foundry Agent 管理 WEB アプリ

Azure の **Foundry Agent** を CRUD・実行できる WEB アプリケーションを作る学習プロジェクト。
ユーザーはモデルとシステムプロンプトを指定してエージェントを作り、一覧・編集・削除し、作ったエージェントとチャットできる。

## 何を作るか

- **エージェント CRUD**：モデル（デプロイ済みから選択）＋システムプロンプトでエージェントを作成・一覧・編集・削除。
- **チャット**：作成したエージェントと会話する（会話の作成・一覧・削除）。

## 技術スタック

| 層 | 採用 | 方針 |
|---|---|---|
| フロントエンド | **Cycle.js** | 学習の為にあえて採用。FRP＋「副作用＝ドライバ」を体験する |
| バックエンド | **Python / FastAPI** | Foundry 操作は REST 直叩きせず **SDK（azure-ai-projects）を最大限使う** |
| データベース | **PostgreSQL** | ローカルは Docker、Azure は Flexible Server |
| IaC | **Bicep** | Foundry 一式＋PostgreSQL＋ロール割当まで |

## MVP の線引き

- **やる**：AOAI モデルのみ／**prompt agent のみ**／ツール非対応の CRUD ＋ 非ストリーミングのチャット。
- **やらない（発展課題）**：トークンのストリーミング表示、メッセージ本文の Postgres 二重保存、
  バージョン履歴 UI、利用者認証（Entra/MSAL）、ツール対応・複数モデル種別。

確定した設定の一覧と「なぜ」は [rough/mvp/README.md](./rough/mvp/README.md) が正本。

## フォルダの歩き方

着手前の**調査 → 計画 → 実装**という流れでフォルダが分かれている。上から順に読むと設計意図を追える。

| フォルダ | 役割 | まず開くファイル |
|---|---|---|
| [research/](./research/) | 事前調査と**フレームワーク蓄積ナレッジ**。スタックの妥当性・各論点・各 FW の API メモ | [research/README.md](./research/README.md) |
| [rough/](./rough/mvp/) | 調査を踏まえて**確定した MVP プラン**（設定・スコープ・データ／API 契約） | [rough/mvp/README.md](./rough/mvp/README.md) |
| [imple/](./imple/) | MVP を**実装着手できる粒度**に落とした設計・スキーマ・実装順（コードは原則書かない） | [imple/README.md](./imple/README.md) |
| [cyclejs/](./cyclejs/) | Cycle.js 本体リポジトリの**ローカルコピー**（参照専用）。docs・examples を読む | `cyclejs/docs/content/` |
| [azure-ai-projects/](./azure-ai-projects/) | Foundry データプレーン SDK の**ローカルコピー**（参照専用）。samples が API の正本 | `azure-ai-projects/docs/subclients.md` |

> ローカルコピー（`cyclejs/` `azure-ai-projects/`）は**外部リポジトリの取り込みなので原則編集しない**。
> 読み方・調べ方の作法は CLAUDE.md（このフォルダ直下）にまとめてある。

## 読む順序（おすすめ）

1. この README で全体像 →
2. [research/](./research/) で「なぜこのスタックか」「各 FW の当たり」 →
3. [rough/mvp/README.md](./rough/mvp/README.md) で「確定した MVP」 →
4. [imple/README.md](./imple/README.md) で「どの順に何を作るか」。

## 参考フォルダ（リポジトリ内の既習資産）

- `learn/foundry/prompt_agent/README.md` … プロンプトエージェントの構築・CRUD・呼び出しの参考
  （リソース構築は本プロジェクトでは Bicep で行うため、参考にするのは Agent の CRUD・呼び出し箇所）。
- `learn/db/simple/` … PostgreSQL Flexible Server の Bicep・`psycopg`・ファイアウォール操作の既習例。

## 参考文献

- [Foundry 概要](https://learn.microsoft.com/en-us/azure/foundry/what-is-foundry)
- [Cycle.js 導入](https://cycle.js.org/getting-started.html)
