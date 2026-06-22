# 実装計画（imple）— インデックス

[rough/mvp/](../rough/mvp/) で確定した MVP プランを、**実装に着手できる粒度**へ落とし込んだもの。
ここはコードを書く前の「設計・スキーマ・実装順」を確定させる場所であり、**コードは原則書かない**
（先に決めておくべき DDL・SDK 呼び出しの型・契約など、決め打ちが必要なものだけ例外的に最小限掲載）。

> 上位の確定事項（A-1〜F-2 の論点表・スコープ）は [rough/mvp/README.md](../rough/mvp/README.md) が正本。
> ここではそれを前提に、各ステップで「何を・どの順で・どう設計して作るか」を詰める。

---

## 読む順序

1. **共通リファレンス**（全ステップで参照。先に目を通す）
   - [common-architecture.md](./common-architecture.md) — 全体設計・認証・設定・フォルダ構成・依存・用語
   - [common-schema-api.md](./common-schema-api.md) — データの所在・PostgreSQL スキーマ検討・REST API 契約・SDK マッピング
2. **ステップ別**（この順で実装。各ステップは「動かして確かめる」まで含む）
   - [step-1-infra.md](./step-1-infra.md) — Bicep（Foundry＋PostgreSQL＋ロール割当）＋ローカル Docker DB
   - [step-2-backend-skeleton.md](./step-2-backend-skeleton.md) — FastAPI 骨組み・`GET /api/models`・エージェント CRUD
   - [step-3-postgres.md](./step-3-postgres.md) — psycopg 接続・`conversations` インデックス・会話 CRUD
   - [step-4-chat.md](./step-4-chat.md) — 非ストリーミングのチャット（responses / conversation items）
   - [step-5-frontend.md](./step-5-frontend.md) — Cycle.js（Vite・MVI・onion state・HTTP ドライバ）

---

## なぜこの順序か（依存関係）

```text
step-1 (infra)          : 以降すべての前提（Foundry endpoint・モデルデプロイ・DB が無いと何も動かない）
   └─ step-2 (backend)  : Foundry だけに依存。DB 無しで models / agents CRUD が確認できる ＝ 早期に手応え
        └─ step-3 (db)  : Postgres を足し、会話インデックスを成立させる（chat の土台）
             └─ step-4 (chat) : agents + conversations が揃って初めてチャットが成立
                  └─ step-5 (frontend) : backend の API が固まってから UI を貼る
```

- **垂直に薄く積む**のではなく、「依存の少ない層から確認可能な単位で積む」方針。
  各ステップ末尾の「確認」を通過してから次へ進む（CLAUDE.md: 一度動かして終わりにしない）。
- step-2 と step-3 は backend の中で分けている理由 → エージェント CRUD は **Postgres 不要**で成立し、
  会話だけが Postgres を要する。先に DB 非依存部分を通すと、DB トラブルと Foundry トラブルを切り分けやすい。

---

## 各ステップ共通の「完了の定義」テンプレ

各ステップは以下を満たして初めて「done」とする。

- [ ] 設計どおりのファイルが揃い、`task <recipe>` で起動/適用できる
- [ ] そのステップの「確認シナリオ」が手元で再現する
- [ ] 新出概念があれば `KNOWLEDGE.md` に追記（[common-architecture.md](./common-architecture.md) の用語表が下書き）

---

## このプランで扱わないもの（発展課題・再掲）

トークンストリーミング表示 / メッセージ本文の Postgres 二重保存 / バージョン履歴 UI・`delete_version` /
利用者認証（Entra・MSAL）・パスワードレス DB / ツール対応・複数モデル種別。
詳細は [rough/mvp/README.md](../rough/mvp/README.md) の「やらない」節。
