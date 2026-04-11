# Azure Functions CRUD Sample with Bicep

`bicep/azure_func_crud` は、Python 製のシンプルな CRUD API を Azure Functions on Linux にデプロイするためのサンプルです。Bicep で Azure リソースを作成し、API Management を前段に置いて API キー認証付きで公開します。必要に応じて、Azure OpenAI リソースとモデルデプロイも同じ Bicep で作成し、APIM 配下の別 API として追加できます。

デプロイ後の既存 CRUD API は、APIM の組み込み機能を使って MCP Server としても公開できます。MCP 化の手順と注意点は `MCP.md` に分離しています。

この README は最初に全体像をつかむための入口です。デプロイ手順、API キー取得、ローカル開発時の注意は別ファイルへ分割しています。

## このサンプルで作るもの

- Storage Account
- App Service Plan
- Linux Function App
- API Management
- APIM Product / Subscription
- APIM に管理された CRUD REST API を MCP Server としてエクスポートするための土台
- Azure OpenAI リソースとモデルデプロイ（任意）
- Azure OpenAI への APIM プロキシ API（任意）
- Function コード配布用 Deployment Script

`publishFunctionCode = true` の場合、Bicep デプロイ時に Python コードも Function App へ発行されます。

## API 概要

このサンプルは APIM 経由で API キー認証を行う HTTP API を提供します。

- `GET /items`: 全件取得
- `GET /items/{id}`: 1 件取得
- `POST /items`: 新規作成
- `PUT /items/{id}`: 更新
- `DELETE /items/{id}`: 削除

Azure OpenAI を有効化した場合は、別 API として以下のような公開 URL も追加されます。

- `POST /aoai/deployments/{deploymentId}/chat/completions`
- `POST /aoai/deployments/{deploymentId}/embeddings`

公開 URL は Azure Functions 直下ではなく APIM 側です。Function App 直下の URL はバックエンド用途で、通常の利用者は使いません。

## ファイル構成

- `justfile`: よく使う Azure CLI / Functions Core Tools コマンドの入口
- `main.bicep`: モジュールを呼び出すオーケストレーター
- `modules/core.bicep`: Storage Account と App Service Plan
- `modules/function-app.bicep`: Linux Function App
- `modules/apim.bicep`: API Management、Product、Subscription、Policy
- `modules/function-code-deployment.bicep`: zip deploy 用 Deployment Script
- `main.bicepparam`: Git に含める共通デフォルト値
- `main.local.bicepparam.example`: ローカル専用上書きパラメータの雛形
- `python/function_app.py`: CRUD API 実装
- `test.http`: API 確認用の REST Client リクエスト集
- `MCP.md`: APIM 組み込み MCP Server 機能で CRUD API を公開する手順

Azure OpenAI を APIM に追加する場合は、`main.local.bicepparam` などで `enableAzureOpenAiApi = true` を指定します。必要に応じて `azureOpenAiLocation`、`azureOpenAiDeploymentName`、`azureOpenAiModelName`、`azureOpenAiModelVersion`、`azureOpenAiDeploymentSkuName`、`azureOpenAiDeploymentCapacity` を上書きしてください。`japaneast` で `gpt-4o-mini` を使う場合は、`azureOpenAiDeploymentSkuName = 'GlobalStandard'` が必要です。

## 最短手順

1. リソースグループを作成する
2. 必要なら `main.local.bicepparam` を作る
3. `just deploy` または `just deploy-local` でデプロイする
4. `just api-key` で APIM の API キーを取得する
5. `test.http` または PowerShell で疎通確認する
6. 必要なら `MCP.md` に沿って CRUD API を MCP Server として公開する

最初に使うコマンドだけ書くと以下です。

```powershell
just group-create
just init-local-param
just deploy
just outputs
just api-key
```

詳細は以下を参照してください。

- [DEPLOYMENT.md](./DEPLOYMENT.md): デプロイ手順、出力値、API キー取得、動作確認
- [DEVELOPMENT.md](./DEVELOPMENT.md): ローカル実行、コード配布、運用上の注意、Git 管理ルール
- [MCP.md](./MCP.md): APIM 組み込み MCP Server 機能の利用手順、VS Code 接続例、注意点

## 前提条件

- Azure サブスクリプション
- Azure CLI
- Bicep CLI または Azure CLI の Bicep サポート
- Azure にログイン済みであること
- Just
- Azure OpenAI リソース作成とモデルデプロイの権限（AOAI を有効化する場合）

ローカル実行や手動発行も行う場合は以下も必要です。

- Python 3.11 以上
- Azure Functions Core Tools
- VS Code REST Client 拡張機能

## 参考

- [DEPLOYMENT.md](./DEPLOYMENT.md)
- [DEVELOPMENT.md](./DEVELOPMENT.md)
- [MCP.md](./MCP.md)
- `python/function_app.py`
- `test.http`
