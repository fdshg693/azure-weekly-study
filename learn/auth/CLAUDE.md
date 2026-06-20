# Azure における認証・認可の学習

OAuth 2.0 / OpenID Connect を土台に、Entra ID を使った認証・認可を、プロジェクトごとにサブフォルダで分割して学ぶ。
各プロジェクトは「**まず一般概念（ベンダー非依存）→ Entra での実装**」「**設定を出し入れして因果を確かめる**」という、このリポジトリ共通の方針に従う。
構築・実行はユーザー自身が行い、AI が Azure 上で実行することはない。

- `./PLAN.md`：この先のプロジェクト候補・学ぶ概念・依存関係・進め方のグループ分け

## 使用技術

- 基本は Bicep, just, Azure CLI
    - just でコマンドを簡略化・集約
    - 環境構築は可能な限り Bicep、Bicep がカバーできない／すべきでない箇所は Azure CLI（例：アプリ登録）
- ただし**クライアント側の認証**を扱うプロジェクトでは、必要に応じてフロントエンドのコードも書く
    - 例：SPA ログインは MSAL.js を使うため、ビルド不要の**バニラ JS + MSAL.js（CDN）**で最小構成にする

## 各プロジェクト共通ファイル構成

細かく分ければよいわけではなく、可読性・理解しやすさを最優先に分割する。

- `justfile`：アプリ登録・設定生成・ローカル実行などのコマンドをまとめる
    - プロジェクトが複雑になる場合は、justfileではなくTaskfile(Taskfile.yml等)を利用すること
- `README.md`：このプロジェクトで行う内容・手順・学習の流れ
- `KNOWLEDGE.md`：このプロジェクトで新たに出た用語・概念（前のプロジェクトでカバー済みの語は含めない）
- `PLAN.md`（任意）：そのプロジェクト固有の設計方針（大きめのプロジェクトのみ）
- `MERMAID.md`（任意）：認証フロー／構成を mermaid で表現
- `*.bicep` ／ フロントエンドのソース：内容に応じて

## プロジェクト一覧

### entra-spa-login

`./entra-spa-login`

`auth` の最初のプロジェクト。**バニラ JS + MSAL.js** だけで動く SPA から Entra ID にサインインし、ログイン状態とユーザー情報（ID トークンのクレーム）を画面に出す「**認証の最小ループ**」を学ぶ。
OAuth 2.0 / OpenID Connect の登場人物（リソースオーナー・クライアント・IdP）、**ID トークン**（身分証）と**アクセストークン**（API への通行証）が別物であること、SPA がパブリッククライアントゆえ **Authorization Code Flow + PKCE** を使う理由、**リダイレクト URI の完全一致**を、設定を出し入れして（リダイレクト URI をわざと壊す／スコープを足し引きして 2 種のトークンを見比べる）確かめる。アプリ登録は az CLI で行い、自前 API は持たず Microsoft Graph（`User.Read`）を **dynamic consent** で消費するだけ、という「**クライアント側・認証のみ**」の最小スコープに絞る（保護対象の自前 API や認可は後続プロジェクトへ）。

### api-protect

`./api-protect`

`auth` の 2 つ目のプロジェクト（[PLAN.md](./PLAN.md) の案1）。`entra-spa-login` の「クライアント側・認証のみ」の続きとして、初めて**リソースサーバー側**（自前 API）を作る。SPA から「**自前 API 宛**」のアクセストークン（委任スコープ `access_as_user`）を取得し、**Node 組み込み HTTP + `jose`** の最小 API がそのトークンの**署名（JWKS）・`aud`・`scp`** を検証する。アプリ登録は**クライアント(SPA)とリソースサーバー(API)で 2 つに分け**（API 側は `Expose an API`、SPA 側は `requiredResourceAccess`）、`just register` が一括作成・配線する。前プロジェクトの Graph 宛トークンとの `aud`/`scp` の違い、**401（認証）と 403（認可）の違い**を、`AUDIENCE`/`REQUIRED_SCOPE` を出し入れして確かめる。SPA は前プロジェクトをそのまま「自前 API 宛」に作り替えたもの。

### app-roles-rbac

`./app-roles-rbac`

`auth` の 3 つ目のプロジェクト（[PLAN.md](./PLAN.md) の案2）。`api-protect` の「保護された自前 API」を土台に、**認証（誰か）から認可（何をしてよいか）へ**進む。自前 API のアプリ登録に **App ロール**（`Tasks.Read` / `Tasks.Write`）を定義し、ユーザーに割り当てる。発行アクセストークンの **`roles` クレーム**を `api/server.js` が読み、エンドポイントごとに**クレームベースで認可**を出し分ける（`/api/me` はロール不要、`GET /api/tasks` は `Tasks.Read`、`POST /api/tasks` は `Tasks.Write`）。核心は **`scp`（アプリがユーザーの代理で要求した操作範囲）と `roles`（主体に割り当てられた役割）の違い**を 1 つのトークンの中で見比べること。本プロジェクトは複雑化したため **just ではなく Taskfile + `scripts/*.ps1`** を採用（PowerShell の実体を .ps1 に切り出し、Taskfile からは呼ぶだけ）。`task assign -- <role>`/`task unassign -- <role>`/`task roles` でロールを**出し入れ**し、SPA は `forceRefresh` で毎回トークンを取り直すので、**同じユーザー・同じログインのまま 200 ↔ 403 が変わる**ことを体感する。次は案3（confidential-web）／案4（client-credentials-daemon）で「誰が・どこで認証するか」のバリエーションへ。

### confidential-web

`./confidential-web`

`auth` の 4 つ目のプロジェクト（[PLAN.md](./PLAN.md) の案3）。これまで 3 つすべて **SPA ＝ パブリッククライアント**（秘密なし・PKCE・トークンはブラウザ）だったのに対し、初めて **サーバーサイド Web アプリ ＝ コンフィデンシャルクライアント**を作る。**クライアントシークレット**を持ち、認可コードフローの **code→token 交換をサーバーが `client_secret` 付きで完結**（**Node 組み込み HTTP + `crypto` + `jose`**、SDK 不使用で交換の一行を露わにする）。発行トークン（ID/アクセス/リフレッシュ）は**サーバーのメモリに保持**し、ブラウザには **`sid`（httpOnly クッキー）だけ**渡す＝**BFF**。`/api/graph` はサーバーが保持アクセストークンで Graph `/me` を代理呼び出しする。アプリ登録は `task register` が **Web プラットフォーム**（`--web-redirect-uris`）に作り、**クライアントシークレットを発行**（SPA プラットフォームとの違いが肝）。`config.js` 生成も SPA 配信も無い（ブラウザに ID/スコープ/秘密を渡さないのが主題）。`entra-spa-login` の「PKCE で秘密なし」と正面から対比し、`CLIENT_SECRET` を出し入れすると **`invalid_client`** で交換が失敗する／devtools でブラウザに `sid` クッキーしか無いことを確かめる。Taskfile + `scripts/*.ps1`。

### client-credentials-daemon

`./client-credentials-daemon`

`auth` の 5 つ目のプロジェクト（[PLAN.md](./PLAN.md) の案4）。これまで 4 つすべて **「ユーザーがログインする」前提**だったのに対し、初めて **ユーザー不在の認証**を扱う。バッチ／デーモン向けの **Client Credentials Flow** で、アプリ自身のクライアントシークレットだけでトークンを取り、保護 API を呼ぶ。核心は **委任許可（delegated / `scp`・ユーザーの代理）とアプリケーション許可（application / `roles`・アプリそのもの）の違い**を、実際に届くトークンの中身で見比べること（デーモンのトークンには `name`・`scp` が無く、`idtyp=app`、`roles` だけがある）。`register.ps1` は自前 API（**Node 組み込み HTTP + `jose`**、`scp` ではなく `roles` を検証・CORS 無し＝ブラウザ前提でない）に App ロール `Tasks.Process.All` を **`allowedMemberTypes=Application`** で定義し、デーモン（コンフィデンシャル＋シークレット）の `requiredResourceAccess` を **`type=Role`**（委任なら `Scope`）で配線する。クライアントは SPA ではなく **デーモン（Node スクリプト）** で、`config.js` 生成も SPA 配信も無い。`scope` は **`.default` 固定**（client credentials は個別スコープを動的要求できない＝事前の管理者同意で動く）。`app-roles-rbac` がロールを**ユーザー**に割り当てたのに対し、本プロジェクトは**アプリの SP** に割り当てる（`task grant`／`revoke`＝アプリケーション許可の管理者同意の出し入れ、要管理者権限）。同じデーモン・同じシークレットのまま `/api/tasks` が **200 ↔ 403** に変わる。Taskfile + `scripts/*.ps1`。次は案7（managed-identity）でこのシークレットを**消す**／案5（on-behalf-of）でユーザートークンの多段伝播へ。

### on-behalf-of

`./on-behalf-of`

`auth` の 6 つ目のプロジェクト（[PLAN.md](./PLAN.md) の案5）。これまで全て「クライアント → 1 つの API」の 1 段だったのに対し、初めて **多段**（SPA → **中間 API(A)** → **下流 API(B)**）を扱う。核心は **`aud` 境界**：A が受け取るトークンは `aud=api://A`、B は `aud=api://B` しか受け入れない＝**受け取ったトークンはそのまま転送できない**。これを解くのが **On-Behalf-Of(OBO) フロー＝トークン交換**で、A が受け取ったユーザートークンを **assertion** にして（`grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`＋A 自身の `client_secret`＋`requested_token_use=on_behalf_of`、**Node 組み込み HTTP + `jose`**・SDK 不使用で交換の一行を露わにする）B 宛トークンを取り直す。交換後トークンは **`aud=api://B` でありながら主体（`name`/`oid`）は元ユーザーのまま**＝**アイデンティティ伝播**。中間 API(A) は**リソースサーバー兼コンフィデンシャルクライアントの二役**で、A だけがシークレットを持つ（B は普通のリソースサーバー・CORS 無し、A は SPA に呼ばれるので CORS 有り）。`register.ps1` が **3 つのアプリ登録**（B＝スコープ Expose／A＝スコープ Expose＋B への `requiredResourceAccess(type=Scope)`＋シークレット／SPA＝A のスコープのみ要求、**各段は次の段だけ知る**）を作る。学びの肝は 2 つの「出し入れ」：(1) `/api/chain-naive`（生トークンをそのまま B へ転送＝**401**）↔ `/api/chain-obo`（OBO 交換してから呼ぶ＝**200**）で `aud` 境界を体感、(2) `task consent`／`revoke-consent` で **A→B の委任同意（`oauth2PermissionGrant`）** を出し入れし、取り消すと OBO 交換が **AADSTS65001** で失敗（chain-obo が 502）。`client-credentials-daemon` の同意は `appRoleAssignment`（アプリ許可）だったのに対し、こちらは `oauth2PermissionGrant`（委任）＝**委任とアプリ許可で管理者同意の置き場所が違う**。Taskfile + `scripts/*.ps1`、SPA はバニラ JS + MSAL.js。次は案7（managed-identity）で A のシークレットを**消す**／案10（security-hardening）でトークン寿命・条件付きアクセスの作り込みへ。
