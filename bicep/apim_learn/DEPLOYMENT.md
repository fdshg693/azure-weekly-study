# Deployment Guide

このファイルは Azure へのデプロイ手順と、APIM の API キー取得手順だけに絞ったガイドです。

## 0. Azure OpenAI について先に確認

`enableAzureOpenAiApi = true` を指定すると、Azure OpenAI リソース本体と 1 つのモデルデプロイもこのテンプレートで新規作成します。

あわせて、その Azure OpenAI を APIM 配下の `/aoai` API として公開するための APIM 設定も追加します。

そのため、デプロイ成功後に `rg-func-crud-dev` 配下には `Microsoft.CognitiveServices/accounts` の AOAI リソースも増えます。増えるのは主に以下です。

- Azure OpenAI リソース
- Azure OpenAI モデルデプロイ
- APIM サービス
- APIM の `azure-openai-api`
- APIM の Product / Subscription
- APIM の Named Value に保存した AOAI API キー

## 1. リソースグループを作成

`justfile` を使う場合:

```powershell
just group-create
```

引数を変えたい場合:

```powershell
just group-create rg-func-crud-dev japaneast
```

手動で Azure CLI を使う場合:

```powershell
az group create --name rg-func-crud-dev --location japaneast
```

## 2. パラメータを準備

共有してよい既定値は `main.bicepparam` に置きます。個人用設定や固定シークレットを入れたい場合は `main.local.bicepparam` を使います。

- `main.bicepparam`: Git 管理してよい共通値
- `main.local.bicepparam`: Git 管理しないローカル値

`main.local.bicepparam` は `main.local.bicepparam.example` をコピーして作成します。

`justfile` を使う場合:

```powershell
just init-local-param
```

主に確認する値は以下です。

- `prefix`
- `pythonVersion`
- `servicePlanSku`
- `apimSkuName`
- `enableAzureOpenAiApi`
- `azureOpenAiLocation`（既定ではメインの `location` と同じ）
- `azureOpenAiDeploymentName`
- `azureOpenAiModelName`
- `azureOpenAiModelVersion`（空文字なら Azure の既定バージョン）
- `azureOpenAiDeploymentSkuName`
- `azureOpenAiDeploymentCapacity`
- `apimPublisherName`
- `apimPublisherEmail`
- `tags`

Azure OpenAI はモデルごとにリージョン可用性が異なります。`enableAzureOpenAiApi = true` にする場合は、`azureOpenAiLocation` と `azureOpenAiModelName` の組み合わせが利用可能かを事前に確認してください。あわせて deployment SKU も確認してください。たとえば `japaneast` の `gpt-4o-mini` は regional `Standard` ではなく `GlobalStandard` が必要です。

## 3. デプロイ

`justfile` を使う場合:

```powershell
just deploy
```

ローカル上書きパラメータを使う場合:

```powershell
just deploy-local
```

APIM を以前削除していて `ServiceAlreadyExistsInSoftDeletedState` が出る場合は、先に soft-delete された APIM を確認してください。

```powershell
just apim-deleted-list
just apim-deleted-show apim-apimlearnlocal-x3y7rmx5 japaneast
```

同じ名前を再利用したい場合は purge します。

```powershell
just apim-purge apim-apimlearnlocal-x3y7rmx5 japaneast
just deploy-local
```

purge したくない場合は、`main.local.bicepparam` で `suffix` を明示指定して別名へ切り替えてください。

```bicep
param suffix = 'local001'
```

コード配布を無効化したい場合:

```powershell
just deploy-no-code
```

別のリソースグループやパラメータファイルを使う場合:

```powershell
just deploy rg-func-crud-dev main.local.bicepparam
```

手動で Azure CLI を使う場合:

共通パラメータでそのままデプロイする場合:

```powershell
az deployment group create --resource-group rg-func-crud-dev --template-file main.bicep --parameters main.bicepparam
```

ローカル上書きパラメータを使う場合:

```powershell
az deployment group create --resource-group rg-func-crud-dev --template-file main.bicep --parameters main.local.bicepparam
```

コード配布を無効化したい場合:

```powershell
az deployment group create --resource-group rg-func-crud-dev --template-file main.bicep --parameters main.bicepparam publishFunctionCode=false
```

## 4. デプロイ出力で確認する値

成功すると、主に以下が返ります。

- `functionAppName`
- `functionAppUrl`
- `backendApiBaseUrl`
- `apimServiceName`
- `apimGatewayUrl`
- `apiBaseUrl`
- `azureOpenAiApiBaseUrl`（有効時のみ）
- `azureOpenAiAccountName`（有効時のみ）
- `azureOpenAiEndpoint`（有効時のみ）
- `azureOpenAiDeploymentName`（有効時のみ）
- `apiKeyHeaderName`
- `apiKeyCommand`
- `azureOpenAiApiKeyCommand`（有効時のみ）
- `storageAccountName`
- `deployCommand`

利用者向けのエンドポイントは `apiBaseUrl` です。

## 5. API キー取得

ここが一番分かりにくくなりやすいので、値を 1 つずつ変数へ入れる形にしています。

重要なのは、`resourceGroupName` には APIM をデプロイしたリソースグループ名を入れること、`apimServiceName` は先にデプロイ出力から取得しておくことです。

既存の CRUD API を APIM の組み込み機能で MCP Server として公開する場合も、まずここで取得する APIM サブスクリプションキーを使います。MCP 化の具体的な手順は `MCP.md` を参照してください。

### 5-1. デプロイ出力を読む

`justfile` を使う場合:

```powershell
just outputs
```

手動で確認する場合:

```powershell
$resourceGroupName = 'rg-func-crud-dev'
$deploymentName = 'main'

$deployment = az deployment group show --resource-group $resourceGroupName --name $deploymentName | ConvertFrom-Json
$apimServiceName = $deployment.properties.outputs.apimServiceName.value
$apiBaseUrl = $deployment.properties.outputs.apiBaseUrl.value
$azureOpenAiApiBaseUrl = $deployment.properties.outputs.azureOpenAiApiBaseUrl.value
$azureOpenAiDeploymentName = $deployment.properties.outputs.azureOpenAiDeploymentName.value
```

### 5-2. API キーを取得する

`justfile` を使う場合:

```powershell
just api-key
```

Azure OpenAI 用 API キー:

```powershell
just aoai-api-key
```

別のリソースグループやデプロイ名を使う場合:

```powershell
just api-key rg-func-crud-dev main crud-default-subscription
```

手動で取得する場合:

```powershell
$subscriptionId = az account show --query id -o tsv
$resourceManager = (az cloud show --query endpoints.resourceManager -o tsv).TrimEnd('/')

$apiKey = az rest --method post --uri "$resourceManager/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.ApiManagement/service/$apimServiceName/subscriptions/crud-default-subscription/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
```

Azure OpenAI 用 API も有効化した場合は、別 Subscription のキーも取得できます。

```powershell
$azureOpenAiApiKey = az rest --method post --uri "$resourceManager/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.ApiManagement/service/$apimServiceName/subscriptions/azure-openai-default-subscription/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
```

これで `$apiKey` に、APIM へ送る API キーが入ります。

一気に実行したい場合は以下でも構いません。

```powershell
$resourceGroupName = 'rg-func-crud-dev'
$deployment = az deployment group show --resource-group $resourceGroupName --name main | ConvertFrom-Json
$apimServiceName = $deployment.properties.outputs.apimServiceName.value
$apiBaseUrl = $deployment.properties.outputs.apiBaseUrl.value
$subscriptionId = az account show --query id -o tsv
$resourceManager = (az cloud show --query endpoints.resourceManager -o tsv).TrimEnd('/')
$apiKey = az rest --method post --uri "$resourceManager/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.ApiManagement/service/$apimServiceName/subscriptions/crud-default-subscription/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
```

### 5-3. 疎通確認を行うecho

```powershell
Invoke-RestMethod -Method GET -Uri "$apiBaseUrl/items" -Headers @{
  'X-API-Key' = $apiKey
}
```

## 6. REST Client で確認

1. `test.http` の `@baseUrl` を `apiBaseUrl` に合わせる
2. `@apiKey` に取得したキーを設定する
3. 各リクエストを順に実行する

ローカルだけでキーを保持したい場合は、`test.local.http` のようなファイルを使ってください。`*.local.http` は Git 管理対象外です。

## 7. PowerShell で作成系を試す

```powershell
$body = @{
  name = 'ノートPC'
  description = '開発用のラップトップ'
} | ConvertTo-Json

Invoke-RestMethod -Method POST -Uri "$apiBaseUrl/items" -ContentType 'application/json' -Headers @{
  'X-API-Key' = $apiKey
} -Body $body
```

## 8. 補足

- `backendApiBaseUrl` は APIM のバックエンド URL です
- Function App 直下の URL は内部ヘッダー検証で保護されています
- APIM の API キーは `X-API-Key` ヘッダーで送ります
- Azure OpenAI を有効化すると、`/aoai` 配下に別 API と別 Subscription が追加されます
- Azure OpenAI を有効化すると、AOAI リソース本体とモデルデプロイも同時に作成されます

## 9. よくある失敗

### `ResourceNotFound` が出る

以下を確認してください。

- `$resourceGroupName` が実際のデプロイ先と一致しているか
- `$apimServiceName` を先に設定しているか
- `crud-default-subscription` を別名に変えていないか

### AOAI リソースが見当たらない

これはこのテンプレートの現在の仕様です。`enableAzureOpenAiApi = true` は、既存 AOAI を APIM の背後に公開するためのスイッチであり、AOAI 自体をプロビジョニングするスイッチではありません。

AOAI を Azure 上にまだ持っていない場合は、別途 Azure OpenAI リソースを作成してから、その `endpoint` と `apiKey` をこのテンプレートに渡してください。

今回のサンプルをそのままデプロイした場合、実際の値は例えば以下です。

```powershell
$resourceGroupName = 'rg-func-crud-dev'
$apimServiceName = 'apim-apimlearn-x3y7rmx5'
```

`api-general-test` のような別のリソースグループを指定すると、そこに APIM が存在しない限り `ResourceNotFound` になります。

### `ServiceAlreadyExistsInSoftDeletedState` が出る

APIM は削除後もしばらく soft-delete 状態で保持されます。今回のテンプレートは既定でリソースグループから決まる固定名を使うため、同じリソースグループへ再デプロイすると同じ APIM 名が再利用され、このエラーになります。

確認:

```powershell
just apim-deleted-list
just apim-deleted-show apim-apimlearnlocal-x3y7rmx5 japaneast
```

同じ名前を再利用したい場合:

```powershell
just apim-purge apim-apimlearnlocal-x3y7rmx5 japaneast
just deploy-local
```

別名で作り直したい場合:

```bicep
param suffix = 'local001'
```

この `suffix` は `main.local.bicepparam` にだけ入れておくのが安全です。
