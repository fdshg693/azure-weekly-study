# KNOWLEDGE — このプロジェクトで新たに出た用語・概念

過去プロジェクトでカバー済みの語（App Service の基本、az ログイン、ロール等）は省く。

## アーキテクチャ

- **BFF (Backend For Frontend)**
  フロント専用の中間サーバー。ブラウザからは BFF だけを見せ、下流（読み取り API /
  Functions）への振り分けや認証情報の隠蔽を担う。本 MVP では `X-User` の転送と
  読み取り/書き込みのルーティングを行う。

- **CQRS 的な読み書き分離（簡易版）**
  読み取り（FastAPI / App Service・常時起動）と書き込み（Functions / 従量・イベント駆動）を
  別サービスに分ける構成。本来は性能・スケールの都合で分けるが、ここでは
  「常時起動 Web API」と「Serverless」の対比を学ぶための意図的な分割。

## Cosmos DB (NoSQL)

- **パーティションキー**
  データを物理的に分割するキー。同一パーティション内のクエリは速く安い。
  本 MVP では会話を `pairKey`（2 ユーザー名を辞書順連結）でパーティション化し、
  1 会話の取得を単一パーティションのクエリで済ませる。

- **Serverless 課金モデル**
  RU/s を事前予約せず、消費した分だけ課金。学習用途のように負荷が低く断続的なケース向け。

- **Cosmos DB Emulator**
  ローカルで Cosmos を模倣する公式エミュレータ。公開（well-known）のエンドポイント
  `https://localhost:8081` と固定キーを持つ。自己署名証明書なので TLS 検証を切って繋ぐ。

## Azure Cache for Redis / キャッシュ設計

- **read-through キャッシュ**
  読み取り時にまずキャッシュを見て、ミスしたら正本(Cosmos)から取り直してキャッシュに載せる方式。

- **TTL (Time To Live)**
  キャッシュキーの有効期限。切れると次の読み取りで正本から作り直される。
  本 MVP では `CACHE_TTL_SECONDS=60`。

- **stale cache（キャッシュの陳腐化）と結果整合性**
  書き込み時に一部のキャッシュを更新しないと、その閲覧者は古いデータを見続ける。
  本 MVP は **送信者キャッシュのみ更新・受信者キャッシュは放置** することで、
  「受信者は TTL 切れまで新着が見えない」結果整合性を意図的に作り、体験させる。
  - 実運用での正解: 書き込み時に関係する全キャッシュを invalidate（無効化）する。
    本 MVP はその“やらない版”を見せて対比する教材。

- **閲覧者ごとのキャッシュキー**
  `conv:{viewer}:{pairKey}`。同じ会話でも閲覧者別にキャッシュを分けることで、
  「送信者だけ即時・受信者は陳腐化」を表現できる。

## Azure Functions（Python v2 プログラミングモデル）

- **v2 モデル / `function_app.py` のデコレータ**
  `@app.route(...)` でトリガを宣言する新しい書き方（function.json を手書きしない）。

- **`auth_level=ANONYMOUS`**
  関数キー無しで叩ける。MVP・ローカル検証向け。本番で保護するなら FUNCTION/ADMIN に上げ、
  呼び出し側（BFF）が `x-functions-key` を付ける（`FUNCTIONS_KEY`）。

- **Consumption(従量) プラン / Y1**
  リクエスト時だけ起動し従量課金。コールドスタートはあるが安価。
  ローカル実行には `AzureWebJobsStorage`（Azurite で代替）が必要。

## ローカル開発ツール

- **Azurite**
  Azure Storage のローカルエミュレータ。Functions のランタイムが要求する
  `AzureWebJobsStorage` をローカルで満たすために使う。

- **App Service の起動コマンド / `WEBSITES_PORT`**
  Linux App Service で Python(uvicorn) を任意ポートで起動する場合、起動コマンドと
  `WEBSITES_PORT` を合わせる。Node は `process.env.PORT` を自動で受け取る。
