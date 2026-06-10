# entra-spa-login — Entra ID で SPA にログインする

`auth` 配下の最初のプロジェクト。**バニラ JS + MSAL.js だけ**で動く SPA から Entra ID にサインインし、ログイン状態とユーザー情報（ID トークンのクレーム）を画面に表示する、認証の**最小ループ**を体験する。

> 設計の意図・一般概念の整理・スコープ外・今後の発展は [PLAN.md](./PLAN.md) を参照。

## 目的

- SPA から外部 IdP（Entra ID）に**サインイン／サインアウト**できる。
- ログインしているユーザーが誰か（名前・メール・テナント）を表示できる。
- **ID トークン**（身分証）と**アクセストークン**（API への通行証）が別物であることを、実物をデコードして見比べる。
- なぜ SPA は **Authorization Code Flow + PKCE** を使うのかを、設定を出し入れして体感する。

## 前提条件

- **Azure CLI**（`az login` 済み）と、アプリ登録を作成できる権限のある Entra テナント
- **just**（コマンドランナー）
- **Python 3.7+**（ローカル配信に `python -m http.server` を使用。Node 派は下の「補足」参照）
- モダンブラウザ（リダイレクトを伴うため `file://` ではなく `http://localhost` で開く）

## 構成

```
entra-spa-login/
├─ PLAN.md         設計と学習方針
├─ README.md       このファイル（手順・学習の流れ）
├─ KNOWLEDGE.md    新出用語（OIDC / PKCE / トークン）の整理
├─ justfile        アプリ登録(az) / 設定生成 / ローカル配信
├─ .env.example    TENANT_ID / CLIENT_ID / REDIRECT_URI の雛形
├─ .gitignore      .env と生成物 src/config.js を無視
└─ src/
   ├─ index.html   ログイン/ログアウト等のボタンと表示領域だけの最小 UI
   ├─ authConfig.js MSAL の設定（APP_CONFIG → msalConfig 等）
   ├─ auth.js       ログイン処理の本体
   └─ config.js     ← .env から `just config` で生成（gitignore 済み）
```

## 実行手順

すべてこの `entra-spa-login` ディレクトリで実行する。

### 1. アプリ登録（ユーザーが一度だけ実行）

Entra ID 上にアプリ登録オブジェクトを作る。SPA プラットフォームにリダイレクト URI を登録し、自テナント専用（single tenant）で作成する。

```bash
just register     # 出力された appId を控える
just tenant       # テナント ID を表示
```

> このリポジトリの方針どおり、Azure 上にオブジェクトを作る操作は**ユーザーが実行**する（AI は実行しない）。

### 2. 設定の記入

`.env.example` をコピーして `.env` を作り、上で得た値を入れる。

```pwsh
Copy-Item .env.example .env
# .env を編集：CLIENT_ID = appId / TENANT_ID = テナントID / REDIRECT_URI = http://localhost:5173
```

### 3. ローカル配信してログイン

```bash
just serve        # = just config（src/config.js 生成）→ http://localhost:5173 を配信
```

ブラウザで <http://localhost:5173> を開き、「ログイン」を押す。Microsoft のログイン画面に飛び、サインインすると元の画面に戻り、名前・メール・テナントと **ID トークンのクレーム**が表示される。

### 4. 後片付け

```bash
just unregister   # .env の CLIENT_ID のアプリ登録を削除
```

## 学習の流れ（設定を「出し入れ」して因果を確かめる）

このリポジトリ恒例の「スイッチを出し入れして、何が効いているか切り分ける」を認証で行う。

1. **正常系**：`just serve` → ログイン → クレーム表示を確認する。
2. **リダイレクト URI を壊す**：`.env` の `REDIRECT_URI` を登録と違う値（例：ポートを `5174`）にして `just serve` → ログインが **`redirect_uri` 不一致エラー**で止まる。戻り先の一致が厳格であることを体感し、元に戻す。
3. **スコープを出し入れ**：`src/authConfig.js` の `loginRequest.scopes` から `'profile'` を外す → 表示されるクレームが減る。さらに「アクセストークン取得 (Graph)」を押し、**ID トークンと aud / scp が違う**＝別物であることをデコードして見比べる。
4. **テナント種別の対比（任意）**：`src/authConfig.js` の authority を `.../${cfg.tenantId}` から `.../common` 相当に変え、マルチテナントの挙動差を確認して戻す。
5. **サインアウト**：「ログアウト」でセッションが切れ、再ログインが要求されることを確認する。

## 補足

- **Node 派**：`python -m http.server` の代わりに `npx serve src -l 5173` でも配信できる（`justfile` の `serve` レシピを差し替え）。
- `src/config.js` は `.env` から生成される使い捨てファイル。`.env` を変えたら `just config`（または `just serve`）で作り直す。
- 本サンプルは学習用に ID/アクセストークンをブラウザでデコードして表示するが、**本番アプリは自前でトークンを検証・解釈してはいけない**（検証は発行元や API 側の責務）。詳しくは [KNOWLEDGE.md](./KNOWLEDGE.md)。
