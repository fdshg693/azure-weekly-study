# メッセージアプリ

複数のユーザーがメッセージを互いに送りあえる。

## 概要

- ユーザーはアカウントを作成し、ログインすることができます。
- ユーザーは他のユーザーにメッセージを送信することができます。

## MVP (Minimum Viable Product)

### 機能
- 認証は不要（ユーザー名を入力すればログイン可能）
- 二人のユーザー間でメッセージを送受信できる
    - 3人以上のユーザー間でのメッセージングはサポートしない
- どのペアも自由にメッセージをやりとりできる
    - 友達リストやブロック機能はサポートしない
    - 存在する全ユーザーを自由に検索してメッセージを送ることができる
- メッセージはテキストのみで、画像やファイルの送信はサポートしない
- リアルタイム性は不要
    - メッセージの送信者はすぐ自分のメッセージが画面で見えるが、受信者はページをリロードしないと新しいメッセージが見えない
    - メッセージ画面は、キャッシュされたメッセージを表示し、リロードすることで最新のメッセージを取得する
        - 同じユーザーとのメッセージは、キャッシュされたメッセージを表示する
        - メッセージをやりとりしているユーザーの一覧表は、キャッシュされたユーザーの一覧を表示する

### 技術スタック

- フロント: バニラ JavaScript, HTML, CSS（`bff/public/`）
- BFF: Node.js, Express（`bff/`）
- バックエンド
    - 読み取り: python, FastAPI（`api/`）
    - 書き込み: python, Azure Functions（`functions/`）
- インフラ
    - Azure App Service(Web Apps) … BFF と 読み取り API
    - Azure Functions(Serverless) … メッセージ送信
    - Azure Cosmos DB(NoSQL) … users / messages の永続化
    - Azure Cache for Redis(In-memory) … 一覧キャッシュ

- 品質担保: CICD なし / E2E なし / ローカル手動テスト / Bicep / Taskfile（just 不使用）/ PowerShell は `scripts/` に分離

---

## アーキテクチャ（なぜこの構成か）

学習目的として、シンプルなアプリにあえて 4 サービスを使い分ける。

| 層 | 実体 | 役割 |
| --- | --- | --- |
| フロント | バニラ JS | UI。送信は楽観的表示、リロードで再取得 |
| BFF | Express (App Service) | フロント配信 + API 振り分け（読み取り→FastAPI / 書き込み→Functions） |
| 読み取り | FastAPI (App Service) | login / users / conversation を Redis 経由で返す |
| 書き込み | Functions | メッセージ送信。Cosmos へ書き、送信者キャッシュのみ更新 |
| 永続化 | Cosmos DB | users / messages の正本 |
| キャッシュ | Redis | 一覧の read-through キャッシュ（TTL 60s） |

詳しい設計は [PLAN.md](./PLAN.md)、図は [MERMAID.md](./MERMAID.md)、用語は [KNOWLEDGE.md](./KNOWLEDGE.md)。

### キャッシュの肝（この MVP の体験ポイント）
「送信者は即見える / 受信者はリロードしても TTL 切れまで見えない」を、
**閲覧者ごとのキャッシュキー** `conv:{viewer}:{pair}` で表現している。
送信時は送信者のキャッシュだけ更新し、受信者のキャッシュはあえて触らない。
→ **stale cache（陳腐化）と TTL による結果整合性**を手で触って理解する。

---

## ローカルで動かす

### 前提
- Docker Desktop（Cosmos Emulator / Redis / Azurite 用）
- Node.js 20+ / Python 3.11+
- [Task](https://taskfile.dev) と [Azure Functions Core Tools v4](https://learn.microsoft.com/azure/azure-functions/functions-run-local)

### 手順
```pwsh
# 0) 設定ファイルを用意（.env と functions/local.settings.json）
task env-init

# 1) ローカル依存を起動（Cosmos Emulator は初回 1〜2 分かかる）
task local-up

# 2) 3 つのサービスをそれぞれ別ターミナルで起動
task api          # http://localhost:8000  読み取り(FastAPI)
task functions    # http://localhost:7071  書き込み(Functions)
task bff          # http://localhost:3000  BFF + フロント

# 3) ブラウザで開く
task open
```

### 動作確認（コマンドで一通り流す）
```pwsh
task seed     # alice/bob/carol を作り、メッセージを数件投入して会話を表示
```

### キャッシュ陳腐化を体験する（手順）
ブラウザのタブを 2 つ開いて別ユーザーでログインする。

1. タブ A=alice、タブ B=bob でログイン。
2. B(bob) で alice を開く → 会話が **キャッシュされる**（`conv:bob:...`）。
3. A(alice) から bob へメッセージ送信 → A には即表示される（楽観的表示＋送信者キャッシュ更新）。
4. B(bob) でリロード → **まだ新着が出ない**（bob のキャッシュは古いまま）。
5. 60 秒（`CACHE_TTL_SECONDS`）待って B でリロード → TTL 切れで Cosmos から再取得し、**新着が出る**。

> これが「キャッシュ表示 → リロードで最新取得」の正体。TTL を縮める/伸ばすと体験が変わる。

---

## Azure へデプロイ（任意・実リソース作成）

> リポジトリのガードレール上、デプロイは明示的に行う操作。コスト（App Service B1 / Redis Basic /
> Cosmos Serverless）が発生する。学習後は `task destroy` で必ず後片付けする。

```pwsh
# 1) インフラを作成（Cosmos / Redis / App Service x2 / Functions）
task deploy

# 2) 3 アプリのコードを配置
task publish

# 3) 公開 URL を確認してブラウザで開く
task outputs        # bffUrl を確認

# 4) 後片付け（リソースグループごと削除）
task destroy
```

### デプロイ後に体験すること
- `task outputs` の `bffUrl` を開き、ローカルと同じ送受信・陳腐化を Azure 上で確認。
- Cosmos の Data Explorer で `messages` コンテナを見て、`pairKey` パーティションに会話が入っていることを確認。
- Redis のキーを確認して、`conv:{viewer}:{pair}` が閲覧者ごとに分かれていることを体験。
