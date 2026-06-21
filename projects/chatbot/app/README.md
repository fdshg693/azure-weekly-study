# アプリ側の説明（Express + Azure OpenAI チャットボット）

Azure App Service 上で動く Express + EJS アプリの実装解説。**API キーを使わず、マネージド ID / `DefaultAzureCredential` から Azure OpenAI を呼び出す**のがポイント。

> インフラ構築（Terraform）・実行コマンド・デプロイ手順は、親フォルダの [../README.md](../README.md) / [../QUICKSTART.md](../QUICKSTART.md) を参照。

## ファイル

| ファイル | 役割 |
| --- | --- |
| [server.js](server.js) | Express + `openai`（AzureOpenAI クライアント）+ `@azure/identity`、`/auth/*` `/profile` ルートを mount。`/chat` は **Responses API + function calling** でツール実行ループを回す |
| [tools.js](tools.js) | AI が呼べるツール定義と実体。`get_user_profile` は **Entra 設定済み＋OBO サインイン時に、ユーザー本人のトークンを OBO 交換して本物の Graph `/me` を呼ぶ**。未設定時はモックを返す。`list_memos` ほかメモ系ツールは **共有リソースなので常に渡し**、`memos.js` 経由で Function を呼ぶ |
| [memos.js](memos.js) | 全ユーザー共有メモの CRUD クライアント。**OBO ではなく Web App の MI** で Azure Function を呼ぶ（`MEMO_API_SCOPE` のトークンを Bearer 付与）。`MEMO_API_BASE_URL` 未設定時はインメモリ Mock にフォールバック。Function 本体は [../function/](../function/) |
| [auth.js](auth.js) | MSAL Node を使った Entra ID 認可コードフロー + Microsoft Graph `/me` 呼び出し |
| [auth_obo.js](auth_obo.js) | On-Behalf-Of フローの実装（`acquireTokenOnBehalfOf` でトークン交換） |
| [views/index.ejs](views/index.ejs) | Bootstrap 製のシンプルなチャット UI（ヘッダーに「共有メモ」リンク） |
| [views/memos.ejs](views/memos.ejs) | 全ユーザー共有メモの手動 CRUD UI（`/api/memos` を fetch で叩く） |
| [views/profile.ejs](views/profile.ejs) | Graph `/me` から取得したサインインユーザー情報を表示するページ |
| [views/profile_obo.ejs](views/profile_obo.ejs) | OBO フローのトークンクレームを表示するページ |
| [package.json](package.json) | `express` / `ejs` / `openai` / `@azure/identity` / `@azure/msal-node` / `express-session` / `axios` の依存定義 |
| [experiments/](experiments/) | `openai` パッケージの Tools / Function calling を試す実験スクリプト |

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

設定は性質で置き場所を分けている。コードからキー類は一切参照しない。

- **エンドポイント**（環境固有値）: env / App Settings（`AZURE_OPENAI_ENDPOINT`）から注入
- **モデル名・API バージョン・推論強度**（秘密でないアプリ設定）: [`config/models.js`](config/models.js) に集約（コミット対象）
- **命名規約（規約A）**: Azure OpenAI のデプロイ名 = モデル名（`gpt-4o-mini` / `gpt-5`）。Terraform もこの規約でデプロイするため、アプリはデプロイ名を env から受け取らず config の値をそのまま使える。モデルを増やすときは `config/models.js` に 1 エントリ追加するだけ。

> **チャット画面でのモデル切り替え**: `config/models.js` の `CHAT_MODELS` がチャット画面のドロップダウンの選択肢になる。`/chat` は Responses API を使うため推論モデル（`gpt-5`）も非推論モデル（`gpt-4o-mini`）も同じ口で呼べ、違いは `reasoning.effort` を渡すか否かだけ（`reasoningEffort: null` なら渡さない）。server.js はモデルごとに `AzureOpenAI` クライアントを生成してキャッシュし、リクエストの `model` id で選ぶ。未指定・不正な id は `DEFAULT_CHAT_MODEL_ID` にフォールバックする。フロントは選択値を localStorage（`aoai-chat-model`）に保持する。選択肢を増やすには `CHAT_MODELS` に 1 エントリ追加し、同名モデルを Azure にデプロイするだけ。

> **API バージョン注意**: `/chat` は **Responses API**（`openai.responses.create`）を使うため、`config/models.js` の `reasoning.apiVersion` は Responses 対応の新しめのプレビュー版（例: `2025-04-01-preview`）が必要。旧 `2024-10-21` では Responses エンドポイントが無く 404 になる。

### `/chat` のツール実行ループ（function calling）

`/chat` はモデルにツール定義を渡し、モデルがツールを呼んだら実行 → 結果を会話に積み戻して再生成、を繰り返す:

1. `tools.toolsForRequest(req)` が**ログイン状態に応じてツールを出し分ける**（未設定＝モックで常に利用可 / 設定済み＝**OBO サインイン時のみ**）
2. `openai.responses.create({ input, tools })` を呼ぶ
3. 出力に `function_call` があれば `tools.executeTool` で実行し、`function_call_output` を `input` に追加して再度 `create`
4. `function_call` が無くなったら `response.output_text` を返す

#### `get_user_profile` は OBO で「ユーザー本人として」Graph を叩く

このツールの肝は、**チャットの LLM 呼び出し（サーバー ID = `DefaultAzureCredential`）とは別に、Graph 呼び出しだけはサインインしたユーザー本人の委任権限で行う**点。実現方法は **On-Behalf-Of (OBO)**:

| 段階 | 内容 |
| --- | --- |
| サインイン | `/auth/signin-obo` で `api://<client-id>/access_as_user` を要求 → セッションに `aud=api://<client-id>` の初回トークンを保存 |
| ツール実行 | 初回トークンを `acquireTokenOnBehalfOf` で **OBO 交換** → `aud=Graph` のトークンを取得 → `/me` を呼ぶ（[auth_obo.js](auth_obo.js) のヘルパーを共有） |
| 結果 | サーバー ID ではなく**ユーザー本人の権限**で Graph が動く（`_source: "graph-obo"`） |

- **Entra 設定済み + 未サインイン** → ツール定義を AI に渡さない（AI は「サインインを促す」だけ）
- **Entra 設定済み + OBO サインイン済み** → 本物の Graph `/me`
- **Entra 未設定** → モックプロフィール（`_source: "mock"`、Entra なしでツール挙動を試せる）

> **試し方**: トップページの「OBO でサインイン（チャット用）」でサインイン後、チャットで「私の名前とメールは？」と聞くと、AI が `get_user_profile` を呼び OBO 経由で本人の Graph 情報を答える。サインアウトすると同じ質問でもツールが渡らず、サインインを促す返答に変わる。

> **別ユーザーで結果が変わるのを体験する**: `just user-create` で自分とは別のテストユーザー（部署「OBO 検証用テストユーザー」/ 勤務地「大阪オフィス」など）を作成 → 表示された UPN/パスワードでシークレットウィンドウから OBO サインイン → 同じ質問でテストユーザーの情報が返る（＝AI の答えがログインユーザーで変わる）。後片付けは `just user-delete`。コマンドの詳細は [../justfile](../justfile) のテストユーザーセクション参照。

> **権限変更の体験（学習目的）**: Entra で当該ユーザーの `User.Read` 同意を取り消す、またはアプリの OBO 許可（Authorized client applications / Expose an API）を外すと、OBO 交換が `AADSTS` 系エラーになり、ツールが本人情報を取れなくなる様子を観察できる。

### 共有メモツール（`list_memos` ほか）は MI でアプリとして下流を叩く

`get_user_profile` が **OBO（サインイン本人の委任）** だったのに対し、メモ系ツールは対になる
**「アプリ自身（Web App のマネージド ID）の権限で、保護された Azure Function を叩く」**＝アプリ間認証の例。
メモは全ユーザー共有なので本人委任は不要で、`tools.js` でも**ログイン状態に依らず常に AI へ渡す**（Tavily と同じ扱い）。

| 観点 | `get_user_profile`（OBO） | メモ系ツール（MI / app role） |
| --- | --- | --- |
| データ | サインイン本人 | 全ユーザー共有 |
| トークン取得 | 初回トークンを OBO 交換 | `DefaultAzureCredential` で `MEMO_API_SCOPE` を取得 |
| 下流の保護 | Graph 同意（scope） | Function の EasyAuth + app role `Memo.ReadWrite` |
| ツール出し分け | OBO サインイン時のみ | 常に渡す（共有） |

- 実体は [memos.js](memos.js)。`MEMO_API_BASE_URL` が未設定なら**インメモリ Mock**で動くので、Azure を立てずに
  AI ツール・手動 UI（`/memos`）の配線を確認できる。設定すると Function（[../function/](../function/)）を呼ぶ。
- 手動 UI と AI が**同じ `memos.js` → 同じ Function**を経由する。人が `/memos` で足したメモを AI が `list_memos` で読む、
  といった往復を体験できる。
- Azure 上で MI の app role 割り当てを外すと Function が **403** を返す様子を観察できる（学習目的 / `just memo-api-show`）。

## 認証デモページ

チャット機能 (`/`, `/chat`) とは独立した 2 つの追加ページで Entra ID 認証パターンを学習できる。手順は [../QUICKSTART.md](../QUICKSTART.md) を参照。

| ページ | 内容 |
| --- | --- |
| `/profile` | サインインしたユーザーのデリゲートトークンをそのまま Graph に投げる「直接フロー」 |
| `/profile-obo` | サーバー側でもう一段トークン交換する **On-Behalf-Of (OBO) フロー** のデモ |

### 直接フローとの比較

| 観点 | `/profile`（直接） | `/profile-obo`（OBO） |
| --- | --- | --- |
| サインイン時のスコープ | `User.Read` (Graph) | `api://<client-id>/access_as_user` |
| 初回トークンの aud | Graph | アプリ自身 |
| サーバー側で Entra に再リクエスト | なし | あり（OBO 交換） |
| Graph 呼び出しに使うトークン | 初回トークンそのまま | OBO で交換した新トークン |
| 典型ユースケース | シンプルな単一アプリ | 中間 API が下流 API を叩く 3 層構成 |
