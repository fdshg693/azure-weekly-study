# message_app — 実装ガイド（CLAUDE 用）

メッセージアプリ。仕様・設計・用語・図は既存ドキュメントを参照し、ここでは**ファイル配置と実装規約**だけを示す。
実装の際、または齟齬に気づいた際は最優先でこのドキュメントを更新する（あらゆるタスクに優先される）。
v1・v2ともに実装済。

## まずどのドキュメントを読むか

| 知りたいこと | ファイル |
| --- | --- |
| 仕様・MVP範囲・ローカル/Azure 手順 | `README.md` |
| 設計（責務分担・データモデル・キャッシュ戦略・API一覧） | `PLAN.md` |
| 新出の用語・概念 | `KNOWLEDGE.md` |
| 認証/構成のフロー図 | `MERMAID.md` |

これらに書いてある内容はここでは繰り返さない。**実装前に該当ドキュメントを開くこと。**

## バージョン運用（重要）

- **ルート直下の `README/PLAN/KNOWLEDGE/MERMAID` が現行バージョン**（タイトルに `V1.0` 等が付く）。
- `versions/v{N}/` は各バージョン時点のドキュメント**スナップショット**。
- 新バージョンに進めるときは、現行ドキュメントを `versions/v{N}/` へ退避してからルートを更新する。
- 説明はバージョン間で重複させない：前バージョンで説明済みの内容は、次バージョンでは最小限の言及に留める（`README.md` 冒頭の方針に従う）。
- コード自体はバージョンフォルダに分けず、ルート直下の各サービス（`api/` `bff/` `functions/` `infra/`）を直接更新する。`versions/` はドキュメントのみ。

### 現行バージョン: V2.0（**実装済**）
- V1（認証なし・メッセージ送受信）に加え、V2 で **パスワード認証 + メール検証** と **友達リスト** を実装済み。
- 実装の所在（設計の根拠は各ドキュメント参照）：
  - `users` に `email`/`passwordHash`/`emailVerified`/`verifyToken`/`verifyTokenExpires` を追加。新コンテナ `friends`（PK `/owner`）。
  - `functions/`: `signup`(route="signup") / `verify`(route="verify") / `friends` 追加(route="friends" POST)・削除(route="friends/{username}" DELETE) と `email_helper.py`（`EMAIL_MODE` で local/acs 切替）。
  - `api/`: `login`（email/password 検証 → **JWT 発行**、未検証は 403）/ `GET /friends`（read-through キャッシュ）。
  - `bff/`: **JWT 検証ミドルウェア `requireAuth`**（成功で `X-User` 注入、失敗で 401）。`signup`/`verify`/`login` は検証前の例外ルート。
  - `infra/modules/communication.bicep`（ACS + Email、Azure 管理ドメイン）。設定 `JWT_SECRET`/`JWT_TTL_SECONDS`/`ACS_*`/`EMAIL_MODE`/`APP_BASE_URL` を各 App に配線済み。
  - ローカル検証は `task seed-auth`（サインアップ→`.verify-links/<email>.txt` のリンク→ログイン→友達追加）。`task seed` はメッセージ陳腐化デモを認証込みで投入。

## ディレクトリと責務

| パス | 役割 | スタック |
| --- | --- | --- |
| `bff/server.js` | フロント配信 + API振り分け（読み取り→FastAPI / 書き込み→Functions） | Node / Express |
| `bff/public/` | フロント（`index.html` / `app.js` / `styles.css`） | バニラ JS |
| `api/` | 読み取り API（login / users / conversation） | Python / FastAPI |
| `functions/` | 書き込み（メッセージ送信のみ） | Python / Azure Functions v2 |
| `infra/` | `main.bicep` + `modules/`（cosmos/redis/plan/webapp/functions） | Bicep |
| `scripts/` | PowerShell スクリプト（`*.ps1`） | PowerShell |
| `Taskfile.yml` | 全操作のエントリポイント | Task |

機能を足すときは、その機能が**読み取りか書き込みか**で `api/` か `functions/` を選ぶ（CQRS 的分離。理由は `PLAN.md`）。

## 操作・コマンド規約

- 実行は**必ず Taskfile 経由**（`task api` / `task deploy` 等）。`just` は使わない。
- ロジックを Taskfile に直書きしない。実体は `scripts/*.ps1` に分離し、Taskfile からは呼ぶだけ。新規操作も同じ流儀で `scripts/` に追加してから task を生やす。
- デプロイ系（`deploy/publish/destroy`）は実リソースを作る。明示指示があるときだけ実行（リポジトリのガードレールに従う）。

## コード規約

- **設定はすべて環境変数**で受け取り、ローカル（Emulator/docker）と Azure を同一コードで切り替える。直値で接続先を書かない。
  - `.env` / `functions/local.settings.json` は gitignore 済み。変更時は対応する `.env.example` / `local.settings.json.example` も更新する。
- **`store.py` は `api/` と `functions/` に意図的に重複**させている（共有パッケージ化しない＝各アプリを独立デプロイするため）。一方の Cosmos/Redis アクセスを変えたら、もう一方も合わせて検討する。
  - 設定の読み方は異なる：`api/` は `config.py` 経由、`functions/store.py` は `os.getenv` 直読み（Functions の App Settings / local.settings.json から取るため）。
- **Cosmos クエリ**：`from` / `to` は SQL 予約語なので射影せず `SELECT *` してから `store.shape_message()` で整形する。
- **会話のパーティション**は `store.pair_key()`（2 username を辞書順連結）。会話取得は単一パーティションクエリで行う。
- **キャッシュは閲覧者ごとのキー** `conv:{viewer}:{pairKey}`。送信時は**送信者のキャッシュだけ更新し受信者は触らない**（陳腐化を体験させる学習の肝＝勝手に「正しく」invalidate しない）。
- **認証**：V1 は認証なし（client が `X-User` を自己申告）。**V2 は BFF が JWT を検証**し、本人 `username` を下流へ信頼済み `X-User` として注入する（`signup`/`verify`/`login` のみ検証前の例外）。下流（api/functions）は BFF からの `X-User` を信頼する。JWT は api(`login`) が `JWT_SECRET`/HS256 で発行し bff が同じ鍵で検証する（両者で値を一致させる）。
- **コメントは日本語**で、「何を」より**「なぜ」**を書く（既存ファイルの密度・トーンに合わせる）。
- **Bicep** は `main.bicep` がモジュールを束ね、`modules/` に1リソース1ファイル。命名は `main.bicep` の `names` マップに集約する。
