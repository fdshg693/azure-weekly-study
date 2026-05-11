# App Service プロジェクト（Azure OpenAI チャットボット）

Azure App Service（Linux / Node.js 20 LTS）上で動く Azure OpenAI チャットボットを Terraform で一発構築する独立プロジェクト。

公式チュートリアル [Build and deploy an Azure OpenAI (Express.js) chatbot - Azure App Service](https://learn.microsoft.com/en-us/azure/app-service/tutorial-ai-openai-chatbot-node) を Terraform 化したもの。**API キーを使わず、Web App のシステム割り当てマネージド ID から Azure OpenAI を呼び出す**のがポイント。

## 構成

```
ユーザー ──HTTPS──> [Linux Web App (Express + EJS)]
                          │  ManagedIdentity / DefaultAzureCredential
                          ▼
                  [Azure OpenAI: gpt-4o-mini]
```

- **リソースグループ** (`azurerm_resource_group`)
- **App Service Plan** (`azurerm_service_plan`) — Linux / 既定 `B1`（F1 だと npm install でメモリ不足になることがある）
- **Linux Web App** (`azurerm_linux_web_app`) — Node.js 20 LTS、システム割り当てマネージド ID を有効化
- **Azure OpenAI アカウント** (`azurerm_cognitive_account`) — kind=`OpenAI`、`custom_subdomain_name` 付き（Entra ID 認証に必須）
- **モデルデプロイ** (`azurerm_cognitive_deployment`) — `gpt-4o-mini`
- **ロール割り当て** (`azurerm_role_assignment`) — Web App の MI に `Cognitive Services OpenAI User`

## ファイル

| ファイル | 役割 |
| --- | --- |
| [provider.tf](provider.tf) | `azurerm ~> 3.0` プロバイダー設定 |
| [variables.tf](variables.tf) | 名前・リージョン・SKU・OpenAI モデル設定など |
| [main.tf](main.tf) | RG / Plan / Web App / Azure OpenAI / モデルデプロイ / ロール割り当て |
| [outputs.tf](outputs.tf) | Web App URL、OpenAI エンドポイント、動作確認コマンド等 |
| [justfile](justfile) | Terraform 操作・パッケージ・デプロイ・ローカル開発のタスク |
| [app/server.js](app/server.js) | Express + `openai`（AzureOpenAI クライアント）+ `@azure/identity`、`/auth/*` `/profile` ルートを mount |
| [app/auth.js](app/auth.js) | MSAL Node を使った Entra ID 認可コードフロー + Microsoft Graph `/me` 呼び出し |
| [app/views/index.ejs](app/views/index.ejs) | Bootstrap 製のシンプルなチャット UI |
| [app/views/profile.ejs](app/views/profile.ejs) | Graph `/me` から取得したサインインユーザー情報を表示するページ |
| [app/package.json](app/package.json) | `express` / `ejs` / `openai` / `@azure/identity` / `@azure/msal-node` / `express-session` / `axios` の依存定義 |

## 主な変数（デフォルト値）

| 変数 | デフォルト | 説明 |
| --- | --- | --- |
| `location` | `Japan East` | App Service 系のリージョン |
| `openai_location` | `Japan East` | Azure OpenAI のリージョン。モデルの提供状況に応じて変更可 |
| `app_service_plan_sku` | `B1` | `F1` / `B1` / `S1` / `P1v2` / `P1v3` |
| `web_app_name` | `webapp-chatbot-dev-seiwan` | URL `https://<name>.azurewebsites.net` の一部、グローバル一意 |
| `openai_account_name` | `aoai-chatbot-dev-seiwan` | `custom_subdomain_name` にもなる、グローバル一意 |
| `openai_deployment_name` | `gpt-4o-mini` | アプリが `AZURE_OPENAI_DEPLOYMENT` で参照する名前 |

## アプリ側の仕組み

`server.js` は `openai` パッケージの `AzureOpenAI` クライアントを使い、`DefaultAzureCredential` 経由で取得したトークンで認証する:

```js
const credential = new DefaultAzureCredential();
const scope = "https://cognitiveservices.azure.com/.default";
const azureADTokenProvider = getBearerTokenProvider(credential, scope);
const openai = new AzureOpenAI({ endpoint, azureADTokenProvider, deployment, apiVersion });
```

- **App Service 上**: 自動でシステム割り当てマネージド ID のトークンが使われる
- **ローカル開発**: `az login` 済みの CLI 資格情報が使われる（`just grant-self` で自分の Entra アカウントに `Cognitive Services OpenAI User` ロールを付与しておく）

エンドポイント・デプロイ名・API バージョンは App Settings 経由で注入され、コードからキー類は一切参照しない。

## 使い方（Terraform 直叩き）

```powershell
terraform init
terraform plan
terraform apply
```

`terraform output web_app_url` でアクセス先 URL、`verify_commands` 出力に確認用コマンドがまとめられている。

## Just でまとめて操作

```powershell
just              # タスク一覧
just up           # terraform apply → アプリ zip デプロイ
just deploy       # app/ を zip にして Web App に配布
just logs         # ストリーミングログ（OpenAI 呼び出しエラーもここ）
just open         # ブラウザで開く
just destroy      # 後片付け

# ローカル開発
just grant-self   # 自分の Entra アカウントに OpenAI User ロールを付与（初回のみ）
just dev          # AZURE_OPENAI_ENDPOINT を inject して `npm install && npm start`
```

`just up` の流れ:

1. `terraform apply -auto-approve` で全リソース作成（OpenAI のモデルデプロイ含む）
2. `app/` を zip 化（`node_modules` は除外）
3. `az webapp deploy --type zip` で配布。`SCM_DO_BUILD_DURING_DEPLOYMENT=true` により App Service 上で Oryx が `npm install` を実行
4. ロール割り当ては Terraform が同時に行うため、起動直後からマネージド ID 経由で OpenAI を呼べる

> **F1 プランの注意**: チュートリアルでは `B1` を推奨。F1 でも動く可能性はあるが、`openai` + `@azure/identity` の npm install で 1GB のメモリ上限を踏むことがあるため、本プロジェクトは既定で `B1` にしてある。

## Entra ID 認証 + Graph API（`/profile` ページ）

`/profile` は Microsoft Entra ID にサインインしたユーザー情報を Microsoft Graph 経由で表示する追加ページ。チャット機能 (`/`, `/chat`) には影響しない。

参考: [Tutorial: Sign in users and call Microsoft Graph from a Node.js web app (MSAL)](https://learn.microsoft.com/en-us/entra/identity-platform/tutorial-v2-nodejs-webapp-msal)

### 1. App Registration を作成（手動）

Azure ポータル > **Microsoft Entra ID** > **App registrations** > **New registration**:

| 項目 | 値 |
| --- | --- |
| Name | 任意 (例: `chatbot-graph-demo`) |
| Supported account types | `Accounts in this organizational directory only` (シングルテナント) |
| Redirect URI | **Web** / `https://<web_app_name>.azurewebsites.net/auth/redirect` |

作成後:
- **Authentication** > **Front-channel logout URL** に `https://<web_app_name>.azurewebsites.net/` を追加
- **Certificates & secrets** > **New client secret** を作成し値を控える
- **API permissions** で **Microsoft Graph** > **Delegated** > `User.Read` を追加 (既定で付いている)

### 2. Terraform に値を投入

`terraform.tfvars` または `-var` で:

```hcl
entra_tenant_id        = "00000000-0000-0000-0000-000000000000"
entra_client_id        = "11111111-1111-1111-1111-111111111111"
entra_client_secret    = "<App Registration のシークレット値>"
express_session_secret = "<32 文字以上のランダム文字列>"
```

`just up` で再 apply するとアプリ側の App Settings が更新される。`entra_client_id` / `entra_client_secret` が空のままだと `/profile` は 503 を返すだけで、チャットは普通に動く。

### 3. ローカル開発

`http://localhost:3000/auth/redirect` を App Registration の Redirect URI に追加し、環境変数で値を渡す:

```powershell
$env:TENANT_ID="..."; $env:CLIENT_ID="..."; $env:CLIENT_SECRET="..."
$env:REDIRECT_URI="http://localhost:3000/auth/redirect"
$env:POST_LOGOUT_REDIRECT_URI="http://localhost:3000/"
$env:EXPRESS_SESSION_SECRET="dev-secret-please-change"
npm install; npm start
```

## トラブルシューティング

- **チャット送信時に "Azure OpenAI からの応答取得に失敗しました"**
  - `just logs` でスタックトレースを確認。`401` 系ならロール割り当ての反映待ち（数分かかる場合あり）
  - `custom_subdomain_name` が無い OpenAI アカウントだと Entra 認証は失敗するので、`main.tf` の該当行が消されていないか確認
- **モデルデプロイで `RegionNotSupported`**
  - `openai_location` を `eastus` / `swedencentral` 等、対象モデルが提供されているリージョンに変更
- **ローカル `just dev` で 403**
  - `just grant-self` を実行。それでも駄目なら `az account show` で対象サブスクリプションが合っているか確認
- **`/profile` で `AADSTS50011` (Redirect URI mismatch)**
  - App Registration の **Authentication** に登録した Redirect URI が `https://<web_app_name>.azurewebsites.net/auth/redirect` と完全一致しているか確認 (末尾スラッシュ・大小文字も)
- **`/profile` で 503「Entra ID 認証が未設定です」**
  - `terraform output` 後、Web App の App Settings に `CLIENT_ID` / `CLIENT_SECRET` / `TENANT_ID` が入っているか `az webapp config appsettings list` で確認
