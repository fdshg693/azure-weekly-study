# App Service プロジェクト

Azure App Service で最小構成の Linux Web App を Free プラン（F1）にデプロイする独立した Terraform プロジェクト。

## 構成

- **リソースグループ** (`azurerm_resource_group`) — すべてのリソースを束ねるコンテナ
- **App Service Plan** (`azurerm_service_plan`) — Linux / SKU `F1`（無料枠）
- **Linux Web App** (`azurerm_linux_web_app`) — Node.js 20 LTS、`always_on = false`、`https_only = true`

## ファイル

| ファイル | 役割 |
| --- | --- |
| [provider.tf](provider.tf) | `azurerm ~> 3.0` プロバイダー設定。認証は Azure CLI または `ARM_*` 環境変数を使用 |
| [variables.tf](variables.tf) | 名前・リージョン・SKU・タグ等の入力変数（バリデーション付き） |
| [main.tf](main.tf) | リソースグループ / App Service Plan / Linux Web App の定義 |
| [outputs.tf](outputs.tf) | Web App URL、ホスト名、各リソース名、動作確認用 `az` コマンドを出力 |
| [justfile](justfile) | Terraform 操作・アプリのパッケージング・デプロイ・動作確認をまとめたタスク定義 |
| [app/server.js](app/server.js) | Node.js 標準 `http` モジュールだけで動く最小サンプルアプリ（依存ゼロ） |
| [app/package.json](app/package.json) | `npm start` で `server.js` を起動するための定義 |

## 主な変数（デフォルト値）

- `location` = `Japan East`
- `resource_group_name` = `rg-app-service-dev`
- `app_service_plan_name` = `asp-minimal-site-dev`
- `app_service_plan_sku` = `F1`（`F1` / `B1` / `S1` / `P1v2` / `P1v3` のみ許可）
- `web_app_name` = `webapp-minimal-dev-seiwan`（グローバル一意、URL の一部になる）

## 使い方

Terraform を直接たたく場合:

```powershell
terraform init
terraform plan
terraform apply
```

デプロイ後、`terraform output web_app_url` でアクセス先 URL を確認できる。`verify_commands` 出力に `az webapp` 系の確認コマンドがまとまっている。

## Just でまとめて操作

[just](https://github.com/casey/just) をインストールしておくと、Terraform とアプリのデプロイを 1 コマンドで実行できる。

```powershell
just              # タスク一覧
just up           # terraform apply → アプリ zip デプロイ
just deploy       # app/ を zip にして Web App に配布（apply 済み前提）
just logs         # ストリーミングログ
just open         # ブラウザで開く
just destroy      # 後片付け
```

`just up` の流れ:

1. `terraform apply -auto-approve` でインフラ（RG / Plan / Web App）を作成
2. `app/` を `app.zip` に圧縮（PowerShell の `Compress-Archive` を使用）
3. `az webapp deploy --type zip` で Web App に配布。Web App 側の `SCM_DO_BUILD_DURING_DEPLOYMENT=true` により Oryx が `npm start` 用に整備する

依存パッケージが無いので `npm install` のステップは事実上スキップされ、デプロイは数十秒で終わる。
