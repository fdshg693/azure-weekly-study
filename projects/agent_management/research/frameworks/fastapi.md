# FastAPI（バックエンド）— 蓄積ナレッジ

> このファイルは **FastAPI まわりで「分かったこと」を貯める場所**。
> FastAPI はローカルコピーが無いため、深掘りは **公式ドキュメント＋Tavily**。
> 新たに分かったことは**ここへ追記**する（再調査の防止）。

## 概要

- Python の型ヒント＋Pydantic ベースの高速 API フレームワーク。自動バリデーション／OpenAPI ドキュメント生成。
- 本プロジェクトでの要点は **SSE ストリーミング中継**（発展課題）:
  - `from fastapi.responses import StreamingResponse` を `media_type="text/event-stream"` で返す（定番）。
  - もしくは `sse-starlette` / 新しめの FastAPI の `EventSourceResponse`（`event`/`id`/`retry` を扱える）。
  - ジェネレータで `yield f"data: {chunk}\n\n"` を返すだけ。SDK のイベントループをここに流す。

## 確認済みの事実（出典つき。新たに分かったら追記）

| # | 事実 | 出典 |
|---|---|---|
| F1 | SSE 中継は素の `StreamingResponse`（`media_type="text/event-stream"`）で十分。SDK イベントをジェネレータで中継 | Tavily `agent_mgmt_research/0004` |
| F2 | 同期 SDK クライアントなら中継はジェネレータ＋`StreamingResponse`。非同期なら `async def`＋`AsyncAzureOpenAI` | [../decisions/02-architecture-review.md](../decisions/02-architecture-review.md) 3. |
| F3 | フロントは別オリジン（Vite dev）なので **CORS ミドルウェア**が要る | [../decisions/01-open-decisions.md](../decisions/01-open-decisions.md) E-1 |

## 本プロジェクトでの方針（決定済み）

- MVP は**非ストリーミング**（1 リクエスト＝1 完成レスポンス）。SSE は発展課題。
- 認証は **`DefaultAzureCredential`** で Foundry を叩く（バック→Foundry）。
- DB は `psycopg`（同期）で接続。MVP は同期で通す。

## 参考 URL

- 公式: <https://fastapi.tiangolo.com/>
- SSE: <https://fastapi.tiangolo.com/tutorial/server-sent-events>（`EventSourceResponse` の使い方）
- FastAPI×OpenAI ストリーミング（Tavily `0004` で確認）:
  - <https://sevalla.com/blog/real-time-openai-streaming-fastapi>
  - <https://oneuptime.com/blog/post/2026-02-16-how-to-implement-streaming-responses-with-azure-openai-api-in-a-web-application/view>（Azure OpenAI 版・図つき）

## 未調査・次に確認したいこと（TODO）

- [ ] CORS の許可オリジン・メソッドの最小設定（実装時に確定）
- [ ] `StreamingResponse` で SDK の同期ジェネレータをそのまま流せるか（イベントループのブロッキング懸念）
