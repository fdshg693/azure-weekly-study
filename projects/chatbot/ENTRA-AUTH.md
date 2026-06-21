# Entra ID 認証 — 概念とポータル手動設定リファレンス

このプロジェクトの認証まわりの**背景知識**と、`just auth-setup` が自動化している
**ポータル手動設定の手順リファレンス**をまとめたファイル。
実行コマンドの順序は [QUICKSTART.md](QUICKSTART.md)、アプリ側のコード解説は [app/README.md](app/README.md) を参照。

参考: [Tutorial: Sign in users and call Microsoft Graph from a Node.js web app (MSAL)](https://learn.microsoft.com/en-us/entra/identity-platform/tutorial-v2-nodejs-webapp-msal)

---

## 1. このアプリに登場する 3 つの「ID／認証」

| 用途 | 仕組み | 「誰」として動くか |
| --- | --- | --- |
| チャットの LLM 呼び出し（Azure OpenAI） | マネージド ID / `DefaultAzureCredential`（キーレス） | **サーバー**（App Service の MI、ローカルは `az login` の自分） |
| `/profile`・チャットの本人プロフィール（直接フロー） | MSAL 認可コードフロー（`User.Read`） | サインインした**ユーザー本人** |
| `/profile-obo`・チャットの `get_user_profile`（OBO） | MSAL OBO（`acquireTokenOnBehalfOf`） | サインインした**ユーザー本人**（下流 Graph まで委任） |

> チャット本体（LLM）と Graph 呼び出しで ID が違う点が重要。詳細は [app/README.md](app/README.md)。

---

## 2. OBO フローと `aud` の変化

OBO（On-Behalf-Of）は、サーバーが受け取ったユーザートークンを**もう一段 Entra で交換**し、
下流 API（Graph）用のトークンを得る仕組み。

```
[ユーザー]
    │  サインイン
    ▼
[api://<client-id>/access_as_user のトークン]   ← 初回トークン (aud = アプリ自身)
    │  acquireTokenOnBehalfOf
    ▼
[Microsoft Graph スコープのトークン]              ← OBO 交換後 (aud = Graph)
    │  /me 呼び出し
    ▼
[ユーザー固有データ]
```

`/profile-obo` ページでは、画面と App Service Log Stream（`just logs`）の両方に
**初回トークン**と**OBO 交換後トークン**のクレームが出力される。確認ポイント:

- `aud` が `api://<client-id>`（または同 GUID）→ `https://graph.microsoft.com`（または `00000003-0000-0000-c000-000000000000`）に変化
- `scp` が `access_as_user` → `User.Read` に変化

両者の `aud` が変わっていれば OBO が成立している証拠。

「**OBO 失敗テスト**」ボタンは、存在しないリソース `https://nonexistent.invalid/.default` 向けに
OBO 交換を試み、Entra が `AADSTS` 系エラーを返すことを確認するもの。
＝「リクエストがローカルで弾かれているのではなく、実際に Entra に到達している」証拠。

> 直接フロー（`/profile`）と OBO（`/profile-obo`）のスコープ・`aud`・ユースケース比較表は
> [app/README.md](app/README.md#直接フローとの比較) にある。

---

## 3. ポータル手動設定リファレンス（`just auth-setup` の中身）

> **通常は不要**。`just auth-setup` が以下をすべて自動で行い、結果を `auth.auto.tfvars`
> （`*.tfvars` は .gitignore 済み）に書き出す。以下は「内部で何をしているか」を理解する用。
> 自動設定の各スクリプトは [§4 スクリプト一覧](#4-scripts-一覧) を参照。

### 3-1. App Registration を作成

Azure ポータル > **Microsoft Entra ID** > **App registrations** > **New registration**:

| 項目 | 値 |
| --- | --- |
| Name | 任意（例: `chatbot-graph-demo`） |
| Supported account types | `Accounts in this organizational directory only`（シングルテナント） |
| Redirect URI | **Web** / `https://<web_app_name>.azurewebsites.net/auth/redirect` |

作成後:

- **Authentication** > **Front-channel logout URL** に `https://<web_app_name>.azurewebsites.net/` を追加
- **Certificates & secrets** > **New client secret** を作成し値を控える
- **API permissions** で **Microsoft Graph** > **Delegated** > `User.Read` を追加（既定で付いている）

### 3-2. OBO 用の追加設定（`/profile-obo`・チャットツール用）

1. **Expose an API**
   - Application ID URI: `api://<client-id>`（提案値そのまま）
   - **Add a scope**: `access_as_user`
     - Who can consent: `Admins and users`
     - Admin consent display name: 任意（例 `Access app on behalf of user`）
2. **Expose an API > Authorized client applications**
   - 自分自身の `<client-id>` を追加し、`access_as_user` スコープにチェック
   - 同一アプリがクライアント兼ミドルティアとして振る舞うために必要
3. **Authentication > Redirect URIs** に追加
   - `https://<web_app_name>.azurewebsites.net/auth/redirect-obo`
   - ローカル開発する場合は `http://localhost:3000/auth/redirect-obo` も追加
4. **API permissions** は既存の `Microsoft Graph > Delegated > User.Read` のまま（追加不要）

### 3-3. Terraform に値を投入

> `just auth-setup` を使った場合は `auth.auto.tfvars` に自動生成されるため手書き不要
> （`*.auto.tfvars` は Terraform が自動で読み込む）。手動なら `terraform.tfvars` または `-var` で:

```hcl
entra_tenant_id        = "00000000-0000-0000-0000-000000000000"
entra_client_id        = "11111111-1111-1111-1111-111111111111"
entra_client_secret    = "<App Registration のシークレット値>"
express_session_secret = "<32 文字以上のランダム文字列>"
```

`just up` で再 apply するとアプリ側の App Settings が更新される。`entra_client_id` /
`entra_client_secret` が空のままだと `/profile` は 503 を返すだけで、チャットは普通に動く
（チャットの `get_user_profile` はモック応答になる）。

### 3-4. ローカル開発で `/profile` を試す

`http://localhost:3000/auth/redirect` を App Registration の Redirect URI に追加し、環境変数で値を渡す:

```powershell
$env:TENANT_ID="..."; $env:CLIENT_ID="..."; $env:CLIENT_SECRET="..."
$env:REDIRECT_URI="http://localhost:3000/auth/redirect"
$env:POST_LOGOUT_REDIRECT_URI="http://localhost:3000/"
$env:EXPRESS_SESSION_SECRET="dev-secret-please-change"
npm install; npm start
```

---

## 4. scripts 一覧

`az` を直接 justfile に書くと巨大ワンライナーになるため、認証・ユーザー操作系は
[scripts/](scripts/) 配下の PowerShell に分離している。

| スクリプト | 役割 | 呼び出す just タスク |
| --- | --- | --- |
| [scripts/entra-app/setup-entra-app.ps1](scripts/entra-app/setup-entra-app.ps1) | App Registration 作成・リダイレクト URI・ログアウト URL・シークレット・Graph `User.Read`・Expose an API(`access_as_user`)・事前承認・SP をまとめて設定し `auth.auto.tfvars` を生成 | `just auth-setup` |
| [scripts/entra-app/show-entra-app.ps1](scripts/entra-app/show-entra-app.ps1) | アプリの現状（公開スコープ・要求権限・シークレット有効期限・**同意済みスコープ**）を表示 | `just auth-show` |
| [scripts/entra-app/destroy-entra-app.ps1](scripts/entra-app/destroy-entra-app.ps1) | App Registration と `auth.auto.tfvars` を削除 | `just auth-destroy` |
| [scripts/test-user/test-user.ps1](scripts/test-user/test-user.ps1) | OBO 体験用のテストユーザーを作成/確認/削除 | `just user-create` / `user-show` / `user-delete` |
| [scripts/openai-role/openai-role.ps1](scripts/openai-role/openai-role.ps1) | 自分への `Cognitive Services OpenAI User` ロールを付与/確認/剥奪 | `just grant-self` / `aoai-role-show` / `aoai-revoke-self` |
| [scripts/_common.ps1](scripts/_common.ps1) | 上記の共通ヘルパー（Graph の固定 ID・PATCH ユーティリティ等） | （内部利用） |

---

## 5. 同意（consent）について

- `User.Read`・`access_as_user` はいずれも **「Admins and users」が同意可能**にしてあるため、
  管理者同意なしで一般ユーザーが初回サインイン時に自分で同意できる。
- そのため [§4-2 のテストユーザー](QUICKSTART.md#4-2-別ユーザーを作って結果が変わるのを確認)でも、
  作成したユーザー自身がサインイン時に同意するだけで Graph `/me` まで到達できる。
- **権限変更の体験**: Entra で当該ユーザーの同意を取り消す、または Authorized client applications /
  Expose an API の設定を外すと、OBO 交換が `AADSTS` 系エラーになりツールが本人情報を取れなくなる
  （→ [TROUBLESHOOTING.md](TROUBLESHOOTING.md)）。
