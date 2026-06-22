# PostgreSQL（データベース）— 蓄積ナレッジ

> このファイルは **PostgreSQL まわりで「分かったこと」を貯める場所**。
> 既習トピック（`learn/db/simple`）が下敷きなので、深掘りは原則そちらを正とする。

## 概要・役割（決定済み）

- 本プロジェクトでの役割は **「エージェント↔会話インデックス＋アプリメタ」に限定**
  （[../decisions/02-architecture-review.md](../decisions/02-architecture-review.md) 1.・[../decisions/01-open-decisions.md](../decisions/01-open-decisions.md) A-2）。
  Foundry が定義・履歴の正本を持つため、それらは複製せず、Foundry が一覧させてくれない
  `conversation_id` のひも付けなどアプリ固有情報だけを持つ。
- ローカルは Docker（`postgres` イメージ）、Azure は PostgreSQL Flexible Server（`learn/db/simple` と同型）。
- アクセスは Python の `psycopg`（`learn/db/simple` で既習）。接続情報は `.env`／環境変数。
- バック→Postgres 認証は **パスワード**（MVP）。Entra パスワードレスは発展課題。

## 既習資産（リポジトリ内＝最優先で流用）

- `learn/db/simple/` … Flexible Server の Bicep、`psycopg` 接続、ファイアウォール出し入れの実例。
  本プロジェクトの DB 構築・接続はここを下敷きにする。

## 確認済みの事実

| # | 事実 | 出典 |
|---|---|---|
| P1 | 会話インデックス＝立派なリレーショナルデータ。役割を限定しても DB 学習価値は残る | [../decisions/02-architecture-review.md](../decisions/02-architecture-review.md) 4. |

## 参考 URL

- 公式: <https://www.postgresql.org/docs/>
- Flexible Server: <https://learn.microsoft.com/azure/postgresql/flexible-server/>

## 未調査・次に確認したいこと（TODO）

- [ ] `conversations` テーブルの最終スキーマ（[../../imple/common-schema-api.md](../../imple/common-schema-api.md) で詰める）
- [ ] 起動時 DDL でのマイグレーション方針（マイグレーションツールを使うか）
