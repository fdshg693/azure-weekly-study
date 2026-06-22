# Step 4 — チャット（非ストリーミング）

agents（step-2）と conversations インデックス（step-3）が揃ったので、チャット本体を実装する。
MVP は **1 リクエスト＝1 完成レスポンス**（ストリーミングしない）。手本は
[azure-ai-projects/samples/agents/sample_agent_basic.py](../azure-ai-projects/samples/agents/sample_agent_basic.py)
と `learn/foundry/prompt_agent/02_chat.py`（履歴維持の肝）。

> API 契約・代表フローは [common-schema-api.md](./common-schema-api.md) §3-4・§5。

---

## 目的

- `POST /api/conversations/{id}/messages`：ユーザー発話を追加し、`responses.create` で完成応答を返す。
- `GET /api/conversations/{id}/messages`：Foundry の conversation items を読み戻して履歴表示。
- 同じ conversation を使い回すことで **履歴が維持される**（France→首都＝Paris と同型）ことを確認する。

---

## 成果物（ファイル）

```text
backend/app/routers/chat.py   # step-3 の会話 CRUD に messages の GET/POST を追加
```

新規ファイルは増やさない（chat.py に集約）。

---

## 設計メモ

### POST /api/conversations/{id}/messages

手順（[common-schema-api.md](./common-schema-api.md) §5 のフロー後半）：

1. `db.get_conversation(id)` → `foundry_conversation_id`（fcid）と `agent_name` を解決（無ければ 404）。
2. `openai.conversations.items.create(conversation_id=fcid, items=[{type:"message", role:"user", content}])`。
3. `openai.responses.create(conversation=fcid, extra_body={"agent_reference": {"name": agent_name, "type": "agent_reference"}})`。
4. `response.output_text` を `{ role: "assistant", content }` として返す。

- **`agent_reference` の name は会話に紐づく `agent_name`**（Postgres 行から取得）。フロントは渡さない。
- 非ストリーミングなので 1 回の `responses.create` で完成応答。`StreamingResponse` は使わない（発展）。

### GET /api/conversations/{id}/messages

- `id → fcid` 解決後、Foundry の **conversation items を取得**して `[{role, content}]` に整形して返す。
- 取得 API は OpenAI 互換クライアント側（`openai.conversations.items.list` 相当）。
  実際のメソッド名・items の content 構造は実装時に SDK（`openai` パッケージ）で確認し、
  text パートのみ抽出する（MVP はテキスト前提、ツール/画像パートは無視）。

### エラー方針（再掲）

- Foundry 認証失敗（ロール剥奪）は **403/401 を透過**（体験シナリオのため）。
- `id` 不在は 404、Postgres 断は 503、入力不備は 422。

---

## 設計上の検討

- **会話の最初の 1 ターン**：step-3 の会話作成では items を入れずに作り、最初のメッセージはこの POST で送る
  （`sample_agent_basic.py` は create 時に初期 user message を入れているが、MVP は「作成」と「発話」を分けて API を素直に保つ）。
- **title の自動補完（任意）**：最初のユーザー発話の冒頭で `title` を更新する余地（§4-4）。MVP は必須にしない。
- **タイムアウト/長文**：応答生成は数秒かかりうる。フロントは送信中の UI ロックで対応（step-5）。backend 側は素直に await。

---

## 確認シナリオ

```text
# 2 ターン会話で履歴が維持される（prompt_agent の France→首都 と同型）
POST /api/agents/{n}/conversations            → {id}
POST /api/conversations/{id}/messages {content:"What is the size of France in square miles?"}
                                              → assistant 応答（面積）
POST /api/conversations/{id}/messages {content:"And what is the capital city?"}
                                              → "Paris"（前ターンの France 文脈を引き継ぐ）
GET  /api/conversations/{id}/messages         → user/assistant が時系列で読み戻せる
```

- 体験：**instructions を変えて編集（PUT で新版）→ 同じ質問への応答が変わる**（バージョニングと「更新＝新版」を体感）。
- 体験：**モデルデプロイを別モデルに変える → 応答傾向が変わる／無いモデルだとエラー**（step-1 のモデル差し替え）。
- 体験：**Foundry User ロール剥奪 → チャットが 403 → 付け直すと通る**（認証と認可の分離）。

---

## このステップの DoD

- [ ] 2 ターン会話で履歴が維持される（文脈引き継ぎを確認）
- [ ] `GET .../messages` で履歴が読み戻せる（role/content）
- [ ] 認証・モデル・instructions を変えると応答や可否が変わることを体感できる
- [ ] backend の REST が step-5（フロント）に対して固まっている
