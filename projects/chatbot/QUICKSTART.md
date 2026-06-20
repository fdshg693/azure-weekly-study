# QUICKSTART（チャットボット）

**コマンドの実行順だけ**をまとめたファイル。上から順に叩けば構築〜体験〜後片付けまで進む。
概念・注意点・トラブル対処は別ファイルに分離している（下表）。

| 知りたいこと | 参照先 |
| --- | --- |
| 全体像・構成・変数 | [README.md](README.md) |
| アプリ実装（`server.js` / `/chat` ツールループ / OBO ツールのコード） | [app/README.md](app/README.md) |
| 認証の概念（OBO・`aud`・同意）とポータル手動設定リファレンス | [ENTRA-AUTH.md](ENTRA-AUTH.md) |
| エラーが出たとき・環境上の注意（F1 プラン等） | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |

## 前提

- `az login` 済み（対象サブスクリプションが選択されていること。`az account show` で確認）
- Terraform / Node.js 20 / [just](https://github.com/casey/just) がインストール済み

```powershell
just              # 利用可能なタスク一覧を表示
```

---

## 1. インフラ構築・デプロイ

```powershell
just up           # terraform apply → アプリを zip にして Web App へデプロイ
just open         # ブラウザで開く（チャットが動く）
just logs         # 必要に応じてログをストリーミング
```

> `just up` の中身（apply → zip → deploy → ロール割り当て）と F1 プランの注意は [TROUBLESHOOTING.md](TROUBLESHOOTING.md#環境構築) を参照。
> Terraform を直接叩く場合: `terraform init && terraform plan && terraform apply`。

---

## 2. ローカル開発

```powershell
just grant-self   # 自分の Entra アカウントに OpenAI User ロールを付与（初回のみ）
just dev          # AZURE_OPENAI_ENDPOINT を inject して npm install && npm start
```

`http://localhost:3000` でチャットが動く。403 が出たら `just grant-self`（→ [TROUBLESHOOTING.md](TROUBLESHOOTING.md#チャット--openai)）。

---

## 3. Entra ID 認証を有効化（`/profile`・`/profile-obo`・チャットの本人プロフィール）

```powershell
just auth-setup   # App Registration を作成/更新し auth.auto.tfvars を生成
just up           # 生成された値（CLIENT_ID 等）を App Settings に反映
just auth-show    # 公開スコープ・同意済みスコープを確認（読み取り専用）
```

> `auth-setup` が自動でやっていること（Expose an API・`access_as_user`・事前承認・Graph `User.Read` 等）と、ポータルで手動設定する場合の手順は [ENTRA-AUTH.md](ENTRA-AUTH.md) を参照。

---

## 4. OBO チャットを体験する（ログインユーザーで AI の答えが変わる）

### 4-1. 自分でサインインして本人情報を取らせる

1. `just open`（または `just dev`）でアプリを開く
2. ヘッダーの **「OBO でサインイン（チャット用）」** からサインイン（初回は同意画面 → 同意）
3. チャットで「**私の名前とメールは？**」と質問
   → AI が `get_user_profile` を呼び、OBO 経由で本人の Graph 情報を答える
4. サインアウトして同じ質問 → `get_user_profile` が AI に渡らなくなり、本人情報は取得不可。
   代わりに AI はシステムプロンプトの指示でサインインを案内する
   （案内するのはツールではなく**システムプロンプト**。文面はモデル依存）

### 4-2. 別ユーザーを作って結果が変わるのを確認

```powershell
just user-create  # テストユーザーを作成（UPN と初期パスワードが表示される）
just user-show    # 作ったユーザーのプロフィールを確認（読み取り専用）
```

1. **シークレットウィンドウ**でアプリを開く（自分のセッションと混ざらないように）
2. 表示された UPN / パスワードで「OBO でサインイン（チャット用）」
3. 同じ質問 → **テストユーザーの情報**（部署「OBO 検証用テストユーザー」/ 勤務地「大阪オフィス」）が返る

```powershell
just user-delete  # テストユーザーを削除（後片付け）
```

> 仕組み（チャットの LLM はサーバー ID、Graph だけ OBO で本人）と、権限を剥がして失敗を観察する手順は [app/README.md](app/README.md) / [ENTRA-AUTH.md](ENTRA-AUTH.md) を参照。

---

## 5. 後片付け

```powershell
just user-delete  # テストユーザーを削除（作成していれば）
just auth-destroy # App Registration と auth.auto.tfvars を削除
just destroy      # 全 Azure リソースを削除
```

---

## よく使う確認系コマンド

```powershell
just url          # Web App の URL を表示
just logs         # アプリのログをストリーミング
just auth-show    # Entra アプリの状態・同意済みスコープ
just aoai-role-show   # 自分の OpenAI ロール割り当て状況
```
