# Step 5 — フロントエンド（Cycle.js）

backend の REST が固まった後に UI を貼る。学習目的であえて **Cycle.js**（FRP・ドライバ・MVI・onion state）を採用。
最新依存を npm で取得し、ビルドは Vite。同梱の [cyclejs/](../cyclejs/) は**参照専用**（バージョンが古い）。

> 全体像・依存方針は [common-architecture.md](./common-architecture.md) §5、叩く API は
> [common-schema-api.md](./common-schema-api.md) §3。参考実装は同梱 `cyclejs/examples/`（後述）。

---

## 目的

- エージェント一覧／作成・編集フォーム／チャット（会話一覧＋スレッド＋入力）の 3 画面を SPA で。
- **MVI（Model-View-Intent）＋ onion state**、**HTTP ドライバ**で backend を叩く構成を体得する。
- ブラウザから CRUD とチャットが一周することを確認（非ストリーミング）。

---

## 成果物（ファイル）

```text
frontend/
├─ package.json          # @cycle/run @cycle/dom @cycle/http @cycle/state xstream + vite
├─ vite.config.js        # dev server :5173、/api を backend(:8000) にプロキシ（or CORS 直叩き）
├─ index.html            # #main-container を持つ
└─ src/
   ├─ main.js            # run(main, {DOM, HTTP, state})
   ├─ app.js             # ルート component（子を束ねる・画面遷移・onion state の合流）
   ├─ api.js             # backend エンドポイントの request 生成（HTTP ドライバ用 category 付き）
   └─ components/
      ├─ agentList.js    # 一覧・選択・削除
      ├─ agentForm.js    # 作成／編集（編集＝新バージョン）
      └─ chat.js         # 会話一覧＋スレッド＋入力（非ストリーミング）
```

---

## 設計メモ

### ドライバ構成（main.js）

- `DOM`（@cycle/dom）／`HTTP`（@cycle/http）／`state`（@cycle/state の `withState`）の 3 ドライバ。
- `run(withState(main), { DOM: makeDOMDriver('#main-container'), HTTP: makeHTTPDriver() })`。
- ストリームライブラリは **xstream**（Cycle 標準）。

### 状態設計（onion state）

ルート state（案）：

```text
{
  agents: [...],            // GET /api/agents の結果
  models: [...],            // GET /api/models
  selectedAgent: name|null, // 一覧で選択中
  form: { mode: 'create'|'edit', name, model, instructions },
  chat: { conversations: [...], currentId: id|null, messages: [...], sending: bool }
}
```

- 各 component は **lens** で自分の担当スライスだけを見る（`isolate` ＋ onion の `lens`）。
- 画面遷移は「選択状態」で表現（MVP はルーターを使わず state 駆動。`examples/routing-view` は発展で参照）。

### MVI（各 component 共通の型）

- **Intent**：DOM イベント（クリック・input）を意味のあるアクションストリームへ。
- **Model**：アクション＋HTTP レスポンスを畳み込み、onion の reducer（`state$`）を出す。
- **View**：state から VDOM を生成。
- **HTTP**：副作用としてリクエストを `HTTP` シンクへ出し、レスポンスは `sources.HTTP.select(category)` で受ける。

### api.js（HTTP ドライバ用リクエスト生成）

- backend の各エンドポイントに対応する request オブジェクトを生成（`url`, `method`, `send`, `category`）。
- `category` でレスポンスを引き当てる（例：`'agents'`, `'models'`, `'createAgent'`, `'messages'`）。
- ベース URL は dev で `http://localhost:8000`（CORS 許可済み）または Vite proxy 経由の `/api`。

### 画面ごとの要点

| component | 役割 | 叩く API |
|---|---|---|
| agentList | エージェント一覧表示・選択・削除 | `GET /api/agents`, `DELETE /api/agents/{name}` |
| agentForm | 作成／編集（**編集＝新バージョン**）。model はセレクト | `GET /api/models`, `POST /api/agents`, `PUT /api/agents/{name}` |
| chat | 会話一覧＋スレッド＋入力。送信中はロック | 会話 CRUD ＋ `GET/POST .../messages` |

- **編集 UX**：F-1 の確定どおり「最新バージョンのみ表示」。編集保存＝裏で新バージョン作成（UI には version 履歴を出さない）。
- **送信中**：`chat.sending` を true にして二重送信を防止。応答が返ったら messages に追記。

---

## 実装順（このステップ内）

1. Vite scaffold ＋ 依存導入 ＋ `index.html`／`main.js`（空の `main` が起動するところまで）。
2. `api.js`（request 生成）と HTTP ドライバの疎通（`GET /api/models` を表示するだけの最小 component）。
3. `agentList` → `agentForm`（CRUD を UI で一周）。
4. `chat`（会話 CRUD → メッセージ送受信）。
5. `app.js` で 3 つを束ね、選択状態で画面を出し分け。

---

## 確認シナリオ

- ブラウザから：**モデル選択 → エージェント作成 → 一覧に出る → 編集（新版）→ チャットで応答が変わる → 会話削除 → エージェント削除**が一周する。
- 体験：**instructions を編集して保存（新版）→ 同じ質問への応答が変わる**ことを UI 上で確認（backend step-4 と連動）。
- CORS：別オリジン（:5173→:8000）でも XHR が通る（backend の `FRONTEND_ORIGIN` 許可が効いている）。

---

## 発展（このステップでは作らない）

- **トークンストリーミング表示**：`EventSource` のカスタムドライバを自作（同梱 `examples/custom-driver` が手本）。
  backend 側は `StreamingResponse` ＋ `responses.create(stream=True)`（`sample_agent_stream_events.py`）。
- ルーティング（`examples/routing-view`）、バージョン履歴 UI。

---

## このステップの DoD

- [ ] `task frontend` で Vite dev が :5173 で起動する
- [ ] ブラウザから CRUD とチャットが一周する
- [ ] MVI＋onion state＋HTTP ドライバの構成になっている（学習目的の達成）
- [ ] `task dev` で DB→backend→frontend が一括起動し、全体が動く
