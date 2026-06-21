# PLAN — メッセージアプリ MVP 設計

`README.md` の MVP 仕様を実装に落とすための設計メモ。各コンポーネントの責務、データモデル、
キャッシュ戦略、ローカル/Azure の対応関係をここに固定する。

## 全体構成（4 サービスの役割分担）

学習目的として、シンプルなアプリにあえて 4 つの Azure サービスを使い、それぞれの役割を体験する。

| コンポーネント | 実体 | Azure | 責務 |
| --- | --- | --- | --- |
| Frontend | バニラ JS / HTML / CSS | （BFF が配信） | UI。送信メッセージの楽観的表示、リロードで再取得 |
| BFF | Node.js / Express | App Service (Web App) | フロント配信 + API ゲートウェイ。読み取りは FastAPI、書き込みは Functions へ振り分け |
| Backend(読み取り) | Python / FastAPI | App Service (Web App) | login / users 一覧 / conversation の **読み取り**。Redis 経由で返す |
| Backend(書き込み) | Python / Azure Functions | Functions (Serverless) | メッセージ **送信**。Cosmos へ書き込み + 送信者キャッシュのみ更新 |
| 永続化 | Cosmos DB (NoSQL) | Cosmos DB | users / messages の正本（source of truth） |
| キャッシュ | Redis | Azure Cache for Redis | users 一覧 / conversation の読み取りキャッシュ（TTL 付き） |

**なぜ読み取り=App Service / 書き込み=Functions に分けるか**：常時起動の Web API（読み取り）と、
イベント駆動・従量課金の Serverless（書き込み）の違いを 1 アプリ内で対比して学ぶため。
実運用での最小構成ではないが、本リポジトリは学習目的なので意図的にこの分割を採る。

## 認証（MVP）

認証なし。フロントは入力された username を `localStorage` に保存し、リクエストヘッダ
`X-User: <username>` で「自分が誰か」を伝える。BFF はこれを下流にそのまま転送する。
（本物の認証は別プロジェクト learn/auth/ で扱う。ここではスコープ外。）

## データモデル（Cosmos DB / NoSQL）

DB: `messageapp`

### コンテナ `users`（パーティションキー `/id`）
```jsonc
{ "id": "alice", "username": "alice", "createdAt": "2026-06-21T12:00:00Z" }
```
- `id` = username。ログイン時に upsert（無ければ作る = サインアップ兼ログイン）。

### コンテナ `messages`（パーティションキー `/pairKey`）
```jsonc
{
  "id": "<uuid>",
  "pairKey": "alice__bob",     // 2 人の username を辞書順ソートして "__" で連結
  "from": "alice",
  "to": "bob",
  "text": "hello",
  "createdAt": "2026-06-21T12:01:00Z"
}
```
- 会話は 2 人ペア固定（3 人以上は非サポート）。`pairKey` でパーティション分割すると、
  1 会話の取得が単一パーティション・クエリで済む。

## キャッシュ戦略（Redis・サーバー側）

README の「キャッシュされたメッセージを表示し、リロードで最新取得」「送信者は即見えるが
受信者はリロードするまで見えない」を、**閲覧者ごとのキャッシュキー**で表現する。

| キー | 内容 | TTL | 更新タイミング |
| --- | --- | --- | --- |
| `users:all` | 全ユーザー一覧 | 60s | TTL 切れで Cosmos から再構築 |
| `conv:{viewer}:{pairKey}` | viewer 視点の会話一覧 | 60s | 下記参照 |

### 読み取り（FastAPI）
1. `conv:{viewer}:{pairKey}` を見る → ヒットすればそれを返す（キャッシュ表示）。
2. ミス（TTL 切れ含む）なら Cosmos から取得して、このキーにセットして返す。

### 書き込み（Functions / メッセージ送信）
1. Cosmos の `messages` に append（正本を更新）。
2. **送信者のキャッシュ `conv:{from}:{pairKey}` だけ**を新メッセージ込みで更新する。
3. 受信者のキャッシュ `conv:{to}:{pairKey}` は **あえて触らない**。

### この設計で体験できること
- 送信者: 楽観的表示に加え、サーバーキャッシュも即更新 → リロードしても自分のメッセージが見える。
- 受信者: 自分のキャッシュは古いまま → **リロードしても TTL(60s) が切れるまで新着が見えない**。
  TTL 経過後にリロードすると Cosmos から再取得して新着が見える。
- → 「キャッシュの陳腐化（stale cache）」と「TTL による結果整合性」を手で触って理解する。

> 注: これは“正しい”キャッシュ無効化ではなく、学習のためにあえて受信者側を無効化しない。
> 実運用では書き込み時に両者のキャッシュを invalidate する。その対比を KNOWLEDGE.md に記す。

## API（BFF が公開し、下流へ振り分け）

| メソッド | パス | 振り分け先 | 説明 |
| --- | --- | --- | --- |
| POST | `/api/login` | FastAPI | username で upsert。`{ username }` を返す |
| GET | `/api/users` | FastAPI | 全ユーザー一覧（自分以外を UI で表示） |
| GET | `/api/conversation?with=<user>` | FastAPI | `X-User` と相手の会話一覧（viewer = X-User） |
| POST | `/api/messages` | Functions | `{ to, text }` を送信。`X-User` が from |

## ローカル / Azure の対応

| 依存 | ローカル | Azure |
| --- | --- | --- |
| Cosmos DB | Cosmos DB Emulator（docker-compose） | Azure Cosmos DB |
| Redis | redis（docker-compose） | Azure Cache for Redis |
| FastAPI | uvicorn | App Service |
| Functions | Azure Functions Core Tools (`func start`) | Functions |
| BFF | `node server.js` | App Service |

接続先は環境変数（`.env`）で切り替える。コードは両対応で書く。

## ディレクトリ構成
```
projects/message_app/
├── README.md / KNOWLEDGE.md / PLAN.md / MERMAID.md
├── Taskfile.yml                # 操作のエントリポイント（just は使わない）
├── docker-compose.yml          # ローカルの Cosmos Emulator + Redis
├── .env.example
├── scripts/                    # PowerShell（巨大ワンライナーを Taskfile に置かない）
├── infra/                      # Bicep（main + modules/）
├── api/                        # FastAPI（読み取り）
├── functions/                  # Azure Functions（書き込み・Python v2 モデル）
└── bff/                        # Express + public/（フロント）
```
