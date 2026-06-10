# api-protect — 自前 API を守る（リソースサーバー側を初めて作る）

`auth` の 2 つ目のプロジェクト（[PLAN.md](../PLAN.md) の案1）。`entra-spa-login` で作った「クライアント側・認証のみ」の最小ループの**直接の続き**として、初めて「**リソースサーバー側**」を作る。

認証は「誰か」を確かめるだけ。実際の価値は「**保護された API を、正しいトークンを持つ相手にだけ使わせる**」こと。前プロジェクトで Graph 宛だったアクセストークンを「**自前 API 宛**」に作り替え、その自前 API が受け取ったトークンの**署名・`aud`（宛先）・`scp`（スコープ）**を検証する。

> 学ぶ概念の整理は [KNOWLEDGE.md](./KNOWLEDGE.md)、フロー図は [MERMAID.md](./MERMAID.md) を参照。

## 目的

- 自前 API（リソースサーバー）を立て、**Bearer アクセストークンを検証**して保護リソースを返せる。
- SPA から「**自前 API 宛**」のアクセストークン（scope = `access_as_user`）を取得し、API を呼べる。
- アクセストークンの **`aud` / `scp`** を見て、前プロジェクトの Graph 宛トークンとの違いを掴む。
- **401（誰か不明）と 403（権限不足）** の違いを、設定を出し入れして体感する。

## 前提条件

- **Azure CLI**（`az login` 済み）と、アプリ登録を作成できる権限のある Entra テナント
- **just**（コマンドランナー）
- **Node.js 18+**（自前 API の実行。依存は `jose` のみで `just api` 初回に自動インストール）
- **Python 3.7+**（SPA のローカル配信に `python -m http.server` を使用）
- モダンブラウザ（`http://localhost` で開く）

## 構成

```
api-protect/
├─ README.md        このファイル（手順・学習の流れ）
├─ KNOWLEDGE.md     新出用語（リソースサーバー / Expose an API / aud・scp 検証 / JWKS / 401・403 / CORS）
├─ MERMAID.md       認証フロー・アプリ登録の関係・検証ロジックの図
├─ justfile         2 つのアプリ登録(az) / 設定生成 / API 起動 / SPA 配信
├─ .env.example     TENANT_ID / SPA_CLIENT_ID / API_CLIENT_ID / REDIRECT_URI / API_BASE_URL の雛形
├─ .gitignore       .env・生成物 src/config.js・api/node_modules を無視
├─ api/             ← 今回初めて作る「リソースサーバー側」
│  ├─ server.js     Node 組み込み HTTP + jose。Bearer を署名/aud/scp で検証する最小 API
│  └─ package.json  依存は jose だけ
└─ src/             SPA（クライアント側）。前プロジェクトを「自前 API 宛」に作り替えたもの
   ├─ index.html    ログイン / 自前 API を呼ぶ / トークン無しで呼ぶ / ログアウト
   ├─ authConfig.js MSAL 設定（apiRequest = api://<API>/access_as_user）
   ├─ auth.js       ログイン処理＋自前 API 呼び出し
   └─ config.js     ← .env から `just config` で生成（gitignore 済み）
```

## 実行手順

すべてこの `api-protect` ディレクトリで実行する。

### 1. アプリ登録（ユーザーが一度だけ実行）

「自前 API」と「SPA」の **2 つのアプリ登録**を作る。API 側は `Expose an API` で委任スコープ `access_as_user` を公開し、SPA 側はそのスコープへの許可を持つ。これらを `just register` が 1 コマンドで作成・配線する。

```bash
just register     # 出力された API_CLIENT_ID と SPA_CLIENT_ID を控える
just tenant       # テナント ID を表示
```

> このリポジトリの方針どおり、Azure 上にオブジェクトを作る操作は**ユーザーが実行**する（AI は実行しない）。

### 2. 設定の記入

`.env.example` をコピーして `.env` を作り、上で得た値を入れる。

```pwsh
Copy-Item .env.example .env
# .env を編集：
#   TENANT_ID     = テナントID
#   SPA_CLIENT_ID = SPA の appId
#   API_CLIENT_ID = 自前 API の appId
#   （REDIRECT_URI / API_BASE_URL は既定のままで可）
```

### 3. 自前 API を起動（別ターミナル）

```bash
just api          # 初回は jose を npm install → http://localhost:3000 で待ち受け
```

### 4. SPA を配信してログイン → API を呼ぶ

別のターミナルで：

```bash
just serve        # = just config（src/config.js 生成）→ http://localhost:5173 を配信
```

ブラウザで <http://localhost:5173> を開き、

1. **「ログイン」** … Microsoft のログイン画面でサインイン（ID トークンのクレームが出る）
2. **「自前 API を呼ぶ」** … 初回は自前 API への同意を求められる → 同意後、`/api/me` の応答と、**送ったアクセストークン（`aud` = 自前 API、`scp` = access_as_user）** が表示される
3. **「トークン無しで呼ぶ」** … 同じ API を Authorization なしで叩き、**401** が返ることを確認する

### 5. 後片付け

```bash
just unregister   # .env の SPA_CLIENT_ID / API_CLIENT_ID のアプリ登録を削除
```

## 学習の流れ（設定を「出し入れ」して因果を確かめる）

「スイッチを出し入れして、何が効いているか切り分ける」をリソースサーバー側で行う。

1. **正常系**：ログイン →「自前 API を呼ぶ」→ 200 と保護データを確認。送ったトークンの `aud` / `scp` を読む。
2. **トークン無し（401）**：「トークン無しで呼ぶ」→ **401 Unauthorized**。「誰だか分からない」と弾かれる＝認証の壁。
3. **宛先(aud)を壊す**：`api/server.js` の `AUDIENCE` をでたらめな値（例 `['api://wrong']`）にして `just api` を再起動 → 正しいトークンでも **401**。リソースサーバーが「自分宛か」を見ていることを体感し、元に戻す。
4. **スコープ不足（403）**：`api/server.js` の `REQUIRED_SCOPE` を存在しない名前（例 `'admin_only'`）に変えて再起動 →「自前 API を呼ぶ」が **403 Forbidden**。401（誰か不明）と 403（権限不足）の違いを掴み、元に戻す。
5. **前プロジェクトとの対比**：`entra-spa-login` の「アクセストークン取得 (Graph)」で出た Graph 宛トークンと、本プロジェクトの自前 API 宛トークンの `aud` / `scp` を見比べる。「アクセストークンは宛先ごとに別物」を確認する。

## 補足

- **2 ターミナル**：自前 API（`just api`）と SPA 配信（`just serve`）は別プロセス。両方を起動した状態で操作する。
- `src/config.js` は `.env` から生成される使い捨てファイル。`.env` を変えたら `just config`（または `just serve`）で作り直す。
- 本サンプルは学習用にクライアント側でもアクセストークンをデコードして表示するが、**トークンの中身を検証・解釈する責務はあくまでリソースサーバー（`api/server.js`）にある**。クライアントは中身を信用してはいけない。
- 次の一歩は案2（app-roles-rbac）。同じ「保護された API」に対し、**ロール（`roles`）で「何をしてよいか」を出し分ける**＝認証から認可へ進む。
