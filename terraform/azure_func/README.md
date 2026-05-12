# Azure Functions × Static Web Apps × HTMX 乱数デモ

Azure Static Web Apps から配信した HTMX ページから、別建ての Azure Functions (Python v2) を CORS 越しに呼び出して乱数を取得するデモ構成。

## 構成

```
[ブラウザ] ──GET──> [Static Web Apps]   index.html (HTMX)
              │
              └──hx-get──> [Function App] /api/random  →  "<span>42</span>"
```

- **リソースグループ** (`azurerm_resource_group`) — すべてのリソースを束ねるコンテナ
- **Storage Account** (`azurerm_storage_account`) — Function App のランタイム用
- **App Service Plan** (`azurerm_service_plan`) — Linux Consumption（`Y1`）
- **Linux Function App** (`azurerm_linux_function_app`) — Python v2、`/api/random` を ANONYMOUS で公開
- **Application Insights** (`azurerm_application_insights`) — 監視・ログ
- **Static Web Apps** (`azurerm_static_web_app`) — HTMX ページの配信（Free SKU）

## ファイル

| ファイル | 役割 |
| --- | --- |
| [provider.tf](provider.tf) | `azurerm ~> 3.0` プロバイダー設定 |
| [variables.tf](variables.tf) | 入力変数（バリデーション付き） |
| [resource_group.tf](resource_group.tf) | リソースグループ |
| [storage_account.tf](storage_account.tf) | Function App ランタイム用 Storage |
| [service_plan.tf](service_plan.tf) | App Service Plan（Linux / Y1） |
| [function_app.tf](function_app.tf) | App Insights と Function App 定義（CORS で SWA ドメイン許可） |
| [static_web_app.tf](static_web_app.tf) | Azure Static Web Apps（Free SKU） |
| [outputs.tf](outputs.tf) | 各種 URL、デプロイトークン、コマンド例 |
| [justfile](justfile) | デプロイ・動作確認の簡便コマンド |
| [scripts/package_web.py](scripts/package_web.py) | `web/index.html` の `__FUNCTION_URL__` を terraform output で置換し `web-dist/` を生成 |
| [python/](python/) | 関数コード（`/api/random` を返す） |
| [web/](web/) | HTMX 配信用 `index.html`（`__FUNCTION_URL__` プレースホルダ） |

## 主な変数（デフォルト値）

- `location` = `Japan East`（Function 系）
- `static_web_app_location` = `East Asia`（Static Web Apps は限定 5 リージョンのみ対応）
- `function_app_name` = `func-simple-dev-seiwan`
- `static_web_app_name` = `swa-htmx-dev-seiwan`
- `python_version` = `3.11`
- `service_plan_sku` = `Y1`

## 前提ツール

- [Terraform](https://developer.hashicorp.com/terraform/install)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)（`az login` 済み）
- [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local)（`func`）
- [Static Web Apps CLI](https://azure.github.io/static-web-apps-cli/)（`npm i -g @azure/static-web-apps-cli`、`swa`）
- [just](https://github.com/casey/just)（`winget install Casey.Just`）

## 使い方（just 経由）

```powershell
just init           # terraform init
just apply          # インフラを作成
just deploy         # Function App と Static Web Apps を両方デプロイ
just open           # ブラウザで HTMX ページを開く
```

ワンショットで全部やるなら：

```powershell
just up             # apply → deploy までまとめて実行
```

利用可能なコマンドは `just`（引数なし）で一覧表示。

## 動作確認

```powershell
just test-func      # 乱数 API を直接叩く
just url            # Static Web App の URL を表示
just func-url       # 乱数エンドポイント URL を表示
```

## 仕組み（HTMX → Function）

`web/index.html` のボタンに `hx-get="__FUNCTION_URL__/api/random"` を仕込んでいる。`just package-web` 実行時に `terraform output -raw function_app_url` の値で置換し、`web-dist/index.html` として SWA にデプロイ。Function 側は HTML 断片 `<span>N</span>` を返すので、HTMX が `#out` に innerHTML として差し込む。

CORS は `function_app.tf` の `cors.allowed_origins` で SWA の `default_host_name` を許可している。

## 後片付け

```powershell
just destroy
```
