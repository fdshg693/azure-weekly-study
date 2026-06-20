# トラブルシューティング & 環境上の注意

エラーが出たとき・環境固有の注意点をまとめたファイル。
コマンドの実行順は [QUICKSTART.md](QUICKSTART.md)、認証の概念は [ENTRA-AUTH.md](ENTRA-AUTH.md) を参照。

---

## 環境構築

### `just up` の中身

1. `terraform apply -auto-approve` で全リソース作成（OpenAI のモデルデプロイ含む）
2. `app/` を zip 化（`node_modules` は除外）
3. `az webapp deploy --type zip` で配布。`SCM_DO_BUILD_DURING_DEPLOYMENT=true` により
   App Service 上で Oryx が `npm install` を実行
4. ロール割り当ては Terraform が同時に行うため、起動直後からマネージド ID 経由で OpenAI を呼べる

`terraform output web_app_url` でアクセス先 URL、`verify_commands` 出力に確認用コマンドがまとまっている。

### ⚠ F1 プランの注意

チュートリアルでは `B1` を推奨。F1 でも動く可能性はあるが、`openai` + `@azure/identity` の
npm install で 1GB のメモリ上限を踏むことがあるため、本プロジェクトは既定で `B1` にしてある。

### API バージョン（Responses API）

`/chat` は **Responses API**（`openai.responses.create`）を使うため、`app/config/models.js` の
`reasoning.apiVersion` は Responses 対応の新しめのプレビュー版（例: `2025-04-01-preview`）が必要。
旧 `2024-10-21` では Responses エンドポイントが無く 404 になる。

---

## チャット / OpenAI

- **チャット送信時に「Azure OpenAI からの応答取得に失敗しました」**
  - `just logs` でスタックトレースを確認。`401` 系ならロール割り当ての反映待ち（数分かかる場合あり）
  - `404` 系なら `app/config/models.js` の `reasoning.apiVersion` が Responses 非対応の古い版になっていないか確認（上記）
  - `custom_subdomain_name` が無い OpenAI アカウントだと Entra 認証は失敗するので、`main.tf` の該当行が消されていないか確認
- **モデルデプロイで `RegionNotSupported`**
  - `openai_location` を `eastus` / `swedencentral` 等、対象モデルが提供されているリージョンに変更
- **ローカル `just dev` で 403**
  - `just grant-self` を実行。それでも駄目なら `az account show` で対象サブスクリプションが合っているか確認

---

## `/profile`（直接フロー）

- **`AADSTS50011`（Redirect URI mismatch）**
  - App Registration の **Authentication** に登録した Redirect URI が
    `https://<web_app_name>.azurewebsites.net/auth/redirect` と完全一致しているか確認（末尾スラッシュ・大小文字も）
- **503「Entra ID 認証が未設定です」**
  - `terraform output` 後、Web App の App Settings に `CLIENT_ID` / `CLIENT_SECRET` / `TENANT_ID` が
    入っているか `az webapp config appsettings list` で確認

---

## `/profile-obo`（OBO フロー）

- **`AADSTS65001`（consent required）**
  - `access_as_user` を Authorized client applications に追加していない、または管理者同意が必要なテナント設定。
    ユーザー個別同意（Admins and users）で公開しているか確認
- **`AADSTS500011`（resource not found）**
  - Application ID URI が `api://<client-id>` で公開されているか、Expose an API のスコープ名が
    `access_as_user` と一致しているかを確認
- **OBO 交換は成功するが Graph 呼び出しで 403**
  - API permissions に `User.Read`（Delegated）が無い、または初回サインイン時に同意していない。
    一度サインアウトして再サインインで同意画面を出す

---

## チャットの `get_user_profile` ツール

- **「OBO でサインインしていません」と返る / ツールが使われない**
  - ヘッダーの「OBO でサインイン（チャット用）」でサインインしているか確認
    （直接フローの `/auth/signin` ではなく **OBO サインイン**が必要）
  - Entra 未設定（`CLIENT_ID` 等が空）の場合はモック応答になる。これは仕様
- **「OBO 交換または Graph 呼び出しに失敗しました」と返る**
  - 初回トークンの失効（約 1 時間）。一度サインアウトして再サインイン
  - 上記 `/profile-obo` の `AADSTS` 系と同じ原因のことが多い

---

## テストユーザー（`just user-create`）

- **作成時に Authorization 系エラー**
  - ユーザーの作成/削除には、サインイン中の自分にディレクトリ権限（User Administrator 相当）が必要
- **`--force-change-password-next-sign-in false` が拒否される / 初回ログインでパスワード変更を求められる**
  - テナントのパスワードポリシー次第。表示されたパスワードで一度サインインし、画面の指示で変更する
- **サインインで MFA / 条件付きアクセスを要求される**
  - テナントが強制している場合は追加手順が必要。検証用なら対象外にできるか管理者に確認
