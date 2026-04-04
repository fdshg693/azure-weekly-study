# APIM 組み込み機能で CRUD API を MCP Server 化する

このサンプルの CRUD API は、Azure API Management に管理された REST API です。デプロイ後に APIM の組み込み MCP Server 機能を使うと、既存の CRUD API 操作を MCP tools として公開できます。

このドキュメントは「既存の CRUD API を、APIM 組み込み機能で MCP Server として公開する」ための実運用メモです。

## 先に結論

- このリポジトリの Bicep は、MCP 化の前提となる CRUD API と APIM をすでにデプロイします
- MCP Server の作成自体は、現時点では Azure portal で行う前提にしています
- 理由は、2026-04-04 時点で Microsoft Learn の ARM/Bicep テンプレート参照に `Microsoft.ApiManagement/service/mcpservers` の公開リソース定義が見当たらないためです
- 既存の API キー取得フローはそのまま MCP 接続にも使えます

## 前提条件

- APIM の SKU が MCP Server 対応ティアであること
- このサンプル既定の `Developer` は対応済みです
- `crud-api` が APIM にデプロイ済みであること
- APIM のサブスクリプションキーを取得できること
- MCP クライアントとして VS Code か MCP Inspector を使えること

対応ティアの考え方は Microsoft Learn に合わせて、`Developer`、`Basic`、`Standard`、`Premium`、および `Basic v2`、`Standard v2`、`Premium v2` を前提にしてください。`Consumption` は対象外として扱うのが安全です。

## 事前に確認すること

### 1. API はすでに APIM 管理下にある

このサンプルでは Bicep が以下を作成します。

- APIM サービス
- `crud-api`
- `crud-product`
- `crud-default-subscription`

MCP Server はこの `crud-api` を元に作成します。

### 2. APIM operation 定義を MCP 向けに保つ

`modules/apim-crud-api.bicep` では、`POST` / `PUT` の JSON 例や `id` パラメータ説明を持たせています。APIM の MCP export はこれらの operation 情報をツール定義に反映するため、CRUD API を変更したら APIM 側の operation 定義も追従させてください。

### 3. 診断ログの設定を見直す

Microsoft Learn では、APIM の global scope で Application Insights や Azure Monitor の診断ログを有効化している場合、`Frontend Response` の `Number of payload bytes to log` を `0` にするよう案内されています。

理由は、MCP の streaming 動作とレスポンス本文のログ取得が干渉するためです。APIM 全体でログを有効にしているなら、MCP 化の前に必ず確認してください。

## MCP Server を作成する手順

1. このサンプルを通常どおりデプロイします
2. `just api-key` で CRUD API 用の APIM サブスクリプションキーを取得します
3. Azure portal で対象の API Management インスタンスを開きます
4. `APIs` 配下の `MCP Servers` を開き、`+ Create MCP server` を選びます
5. `Expose an API as an MCP server` を選びます
6. Managed API に `crud-api` を選びます
7. Tools として以下の operation を選びます

- `list-items`
- `create-item`
- `get-item`
- `update-item`
- `delete-item`

8. MCP Server 名を決めます。例: `crud-mcp`
9. 作成後、`Server URL` を控えます

通常は `https://<apim-service-name>.azure-api.net/<mcp-server-name>/mcp` の形になります。最終的には portal に表示される `Server URL` を正として扱ってください。

## どの認証を使うか

このサンプルは既存の CRUD API を APIM サブスクリプションキーで保護しています。MCP Server への inbound 認証も、まずは同じキー方式に揃えるのが最小構成です。

このリポジトリでは APIM 側のサブスクリプションキー名を `X-API-Key` にしています。そのため、VS Code などの MCP クライアントでも同じヘッダー名でキーを送る想定です。

Microsoft Learn の例では `Ocp-Apim-Subscription-Key` を使っていますが、APIM 側でヘッダー名をカスタマイズしている場合は、その設定に合わせてください。

## VS Code から接続する

一番確実なのは VS Code の `MCP: Add Server` コマンドを使う方法です。

1. Command Palette で `MCP: Add Server` を実行します
2. サーバー種別は HTTP を選びます
3. URL に portal の `Server URL` を入力します
4. 保存先は workspace settings か user settings を選びます
5. 必要なら認証ヘッダーを追加します

手動で設定を書くなら、イメージは次のようになります。

```json
{
  "servers": {
    "crud-mcp": {
      "type": "http",
      "url": "https://<apim-service-name>.azure-api.net/crud-mcp/mcp",
      "headers": {
        "X-API-Key": "<apim-subscription-key>"
      }
    }
  }
}
```

VS Code のバージョンによっては MCP 設定スキーマが更新されることがあるため、実際の保存形式は `MCP: Add Server` で生成された内容を優先してください。

## MCP Server 用ポリシーで考えること

REST API をそのまま MCP 化するだけでも動きますが、MCP Server 専用のポリシーを追加すると運用しやすくなります。

- MCP セッション単位の rate limit
- JWT や Entra ID による inbound 認証
- IP 制限
- 必要なヘッダーの付与や検証

一方で、Microsoft Learn では `context.Response.Body` に触れるポリシーは避けるよう案内されています。レスポンス buffering が起き、MCP の streaming を壊す可能性があるためです。

## 動作確認のポイント

MCP クライアント側で接続後、ツール一覧に次のような CRUD 操作が見えれば第一段階は成功です。

- List items
- Create item
- Get item
- Update item
- Delete item

そのうえで、たとえば次のような依頼を agent mode で実行して確認します。

- `List all items`
- `Create an item named Notebook PC with description Development laptop`
- `Get item <id>`

## うまくいかないときの確認点

- APIM の SKU が MCP 対応ティアか
- MCP Server 作成時に `crud-api` と正しい operations を選んだか
- MCP クライアントが `X-API-Key` を送れているか
- APIM global scope の診断ログがレスポンス本文を記録していないか
- MCP Server ポリシーや API ポリシーで `context.Response.Body` を参照していないか
- `Server URL` ではなく元の REST API URL を VS Code に設定していないか

## 関連ドキュメント

- `README.md`
- `DEPLOYMENT.md`
- `DEVELOPMENT.md`
- Microsoft Learn: Expose REST API in API Management as an MCP server
- Microsoft Learn: About MCP servers in Azure API Management
- Microsoft Learn: Secure access to MCP servers in API Management