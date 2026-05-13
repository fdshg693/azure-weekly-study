// ============================================================================
// シンプルな CRUD Function App + APIM のデプロイ
// ============================================================================
// main.bicep はオーケストレーターとして振る舞い、実リソース定義は modules/ に分割する。
//
// セキュリティモデル：
//   - Function App は System-Assigned Managed Identity で Storage / Key Vault にアクセス
//   - APIM は System-Assigned Managed Identity で Key Vault / Azure OpenAI にアクセス
//   - BACKEND_SHARED_SECRET は Key Vault に格納し、Function App / APIM 双方が参照
//   - Azure OpenAI は disableLocalAuth:true で key 認証を遮断（APIM の MI のみ受け入れ）
//
// デプロイコマンド:
//   az deployment group create \
//     --resource-group <リソースグループ名> \
//     --template-file main.bicep \
//     --parameters main.bicepparam

// ============================================================================
// パラメータ定義
// ============================================================================

@description('Azure リソースをデプロイするリージョン')
param location string = resourceGroup().location

@description('リソース名のプレフィックス（グローバルで一意になるよう調整してください）')
@minLength(1)
param prefix string = 'apimlearn'

@description('一意性を確保するためのサフィックス')
param suffix string = uniqueString(resourceGroup().id)

@description('Python ランタイムのバージョン（3.9, 3.10, 3.11, 3.12, 3.13）')
@allowed(['3.9', '3.10', '3.11', '3.12', '3.13'])
param pythonVersion string = '3.11'

@description('App Service Plan の SKU。Identity-based AzureWebJobsStorage は Premium (EP*) 以上が必要なため、デフォルトを EP1 に設定。Y1 (Consumption) を選んだ場合は Storage 接続が key 認証にフォールバックする必要があるが、本テンプレートでは未対応。')
@allowed(['Y1', 'EP1', 'EP2', 'EP3', 'B1'])
param servicePlanSku string = 'EP1'

@description('API Management の SKU（サンプル用途では Consumption を推奨）')
@allowed(['Consumption', 'Developer', 'BasicV2', 'StandardV2'])
param apimSkuName string = 'Developer'

@description('API Management の publisher 名')
param apimPublisherName string = 'Bicep CRUD Sample'

@description('API Management の publisher メールアドレス')
param apimPublisherEmail string = 'noreply@example.com'

@description('リソースに適用するタグ')
param tags object = {
  Environment: 'Development'
  Project: 'BicepFunctionsCRUD'
  ManagedBy: 'Bicep'
}

@description('Function App のコードもあわせてデプロイするか')
param publishFunctionCode bool = true

@secure()
@description('APIM と Function App 間で共有するバックエンド認証シークレット。Key Vault に格納されます。未指定時はデプロイ時に自動生成（newGuid）されますが、本番では bicepparam の az.getSecret() で受け渡しを推奨。')
param backendSharedSecret string = newGuid()

@description('Azure OpenAI を新規作成し、APIM 配下の別 API として公開するか')
param enableAzureOpenAiApi bool = false

@description('Azure OpenAI をデプロイするリージョン。モデル可用性に応じて変更してください')
param azureOpenAiLocation string = location

@description('Azure OpenAI モデルデプロイ名')
param azureOpenAiDeploymentName string = 'gpt-4o-mini'

@description('Azure OpenAI にデプロイするモデル名')
param azureOpenAiModelName string = 'gpt-4o-mini'

@description('Azure OpenAI モデルバージョン。空文字の場合は Azure の既定バージョンを利用します')
param azureOpenAiModelVersion string = ''

@description('Azure OpenAI モデルデプロイの SKU')
@allowed(['Standard', 'GlobalStandard', 'GlobalBatch'])
param azureOpenAiDeploymentSkuName string = 'Standard'

@description('Azure OpenAI モデルデプロイの容量。利用可能な値はモデルと SKU に依存します')
@minValue(1)
param azureOpenAiDeploymentCapacity int = 10

@description('Azure OpenAI モデルの自動アップグレード方針')
@allowed(['NoAutoUpgrade', 'OnceCurrentVersionExpired', 'OnceNewDefaultVersionAvailable'])
param azureOpenAiVersionUpgradeOption string = 'OnceNewDefaultVersionAvailable'

// ============================================================================
// 名前とコード定義
// ============================================================================
var functionAppName = 'func-${prefix}-${suffix}'
var apimServiceName = 'apim-${prefix}-${take(suffix, 8)}'
var azureOpenAiAccountName = 'aoai-${prefix}-${take(suffix, 8)}'
// Key Vault 名は 3-24 文字、英数字とハイフンのみ。プレフィックスとサフィックスから生成。
var keyVaultName = take('kv-${prefix}-${take(suffix, 8)}', 24)
var functionAppSource = loadTextContent('python/function_app.py')
var hostJsonContent = loadTextContent('python/host.json')
var requirementsTxtContent = loadTextContent('python/requirements.txt')
var functionCodeHash = uniqueString(functionAppSource, hostJsonContent, requirementsTxtContent, pythonVersion)
var deployPythonScript = loadTextContent('scripts/deploy_function_code.py')

// ============================================================================
// モジュール
// ============================================================================
module core './modules/core.bicep' = {
  name: 'coreResources'
  params: {
    location: location
    prefix: prefix
    suffix: suffix
    servicePlanSku: servicePlanSku
    tags: tags
  }
}

// Key Vault は Function App / APIM より先に作成しておく（URI を双方へ渡すため）。
module keyVault './modules/key-vault.bicep' = {
  name: 'keyVaultResources'
  params: {
    location: location
    keyVaultName: keyVaultName
    backendSharedSecret: backendSharedSecret
    tags: tags
  }
}

module azureOpenAi './modules/azure-openai.bicep' = {
  name: 'azureOpenAiResources'
  params: {
    location: azureOpenAiLocation
    azureOpenAiAccountName: azureOpenAiAccountName
    enableAzureOpenAiApi: enableAzureOpenAiApi
    azureOpenAiDeploymentName: azureOpenAiDeploymentName
    azureOpenAiModelName: azureOpenAiModelName
    azureOpenAiModelVersion: azureOpenAiModelVersion
    azureOpenAiDeploymentSkuName: azureOpenAiDeploymentSkuName
    azureOpenAiDeploymentCapacity: azureOpenAiDeploymentCapacity
    azureOpenAiVersionUpgradeOption: azureOpenAiVersionUpgradeOption
    tags: tags
  }
}

module functionApp './modules/function-app.bicep' = {
  name: 'functionAppResources'
  params: {
    location: location
    functionAppName: functionAppName
    servicePlanId: core.outputs.servicePlanId
    storageAccountName: core.outputs.storageAccountName
    pythonVersion: pythonVersion
    tags: tags
    backendSecretUri: keyVault.outputs.backendSecretUri
  }
}

module apim './modules/apim.bicep' = {
  name: 'apiManagementResources'
  params: {
    location: location
    apimServiceName: apimServiceName
    apimSkuName: apimSkuName
    apimPublisherName: apimPublisherName
    apimPublisherEmail: apimPublisherEmail
    functionDefaultHostName: functionApp.outputs.functionDefaultHostName
    tags: tags
    backendSecretUri: keyVault.outputs.backendSecretUri
    enableAzureOpenAiApi: enableAzureOpenAiApi
    azureOpenAiEndpoint: azureOpenAi.outputs.azureOpenAiEndpoint
  }
}

// ロール割り当ては Function App と APIM の MI が確定してから一括で行う。
module roleAssignments './modules/role-assignments.bicep' = {
  name: 'roleAssignments'
  params: {
    storageAccountName: core.outputs.storageAccountName
    keyVaultName: keyVault.outputs.keyVaultName
    functionAppPrincipalId: functionApp.outputs.functionAppPrincipalId
    apimPrincipalId: apim.outputs.apimPrincipalId
    enableAzureOpenAiApi: enableAzureOpenAiApi
    azureOpenAiAccountName: azureOpenAi.outputs.azureOpenAiAccountName
  }
}

// 関数コード配布は最後（ロール割り当て後）に行う。
// 注意: Function App のランタイムが Storage に対する MI 認可を受けるためにロール伝播待ち（最大 5-10 分）が発生する場合がある。
module functionCodeDeployment './modules/function-code-deployment.bicep' = {
  name: 'functionCodeDeployment'
  params: {
    location: location
    publishFunctionCode: publishFunctionCode
    functionAppName: functionApp.outputs.functionAppName
    functionAppSource: functionAppSource
    hostJsonContent: hostJsonContent
    requirementsTxtContent: requirementsTxtContent
    deployPythonScript: deployPythonScript
    functionCodeHash: functionCodeHash
  }
  dependsOn: [
    roleAssignments
  ]
}

// ============================================================================
// 出力
// ============================================================================
@description('Function App の名前')
output functionAppName string = functionApp.outputs.functionAppName

@description('Function App のデフォルト URL')
output functionAppUrl string = functionApp.outputs.functionAppUrl

@description('Function App のバックエンド API URL（APIM からのみ利用）')
output backendApiBaseUrl string = 'https://${functionApp.outputs.functionDefaultHostName}/api'

@description('API Management サービス名')
output apimServiceName string = apim.outputs.apimServiceName

@description('API Management のゲートウェイ URL')
output apimGatewayUrl string = apim.outputs.apimGatewayUrl

@description('利用者向け CRUD API のベース URL')
output apiBaseUrl string = apim.outputs.apiBaseUrl

@description('利用者向け Azure OpenAI API のベース URL。未有効時は空文字')
output azureOpenAiApiBaseUrl string = apim.outputs.azureOpenAiApiBaseUrl

@description('Azure OpenAI リソース名。未有効時は空文字')
output azureOpenAiAccountName string = azureOpenAi.outputs.azureOpenAiAccountName

@description('Azure OpenAI リソースのエンドポイント。未有効時は空文字')
output azureOpenAiEndpoint string = azureOpenAi.outputs.azureOpenAiEndpoint

@description('Azure OpenAI モデルデプロイ名。未有効時は空文字')
output azureOpenAiDeploymentName string = azureOpenAi.outputs.azureOpenAiDeploymentName

@description('利用者が送る API キーのヘッダー名')
output apiKeyHeaderName string = apim.outputs.apiKeyHeaderName

@description('APIM サブスクリプションキーを取得する Azure CLI コマンド')
output apiKeyCommand string = 'az rest --method post --uri "${environment().resourceManager}subscriptions/$(az account show --query id -o tsv)/resourceGroups/${resourceGroup().name}/providers/Microsoft.ApiManagement/service/${apim.outputs.apimServiceName}/subscriptions/${apim.outputs.apimSubscriptionName}/listSecrets?api-version=2024-05-01"'

@description('Azure OpenAI 用 APIM サブスクリプションキーを取得する Azure CLI コマンド。未有効時は空文字')
output azureOpenAiApiKeyCommand string = enableAzureOpenAiApi ? 'az rest --method post --uri "${environment().resourceManager}subscriptions/$(az account show --query id -o tsv)/resourceGroups/${resourceGroup().name}/providers/Microsoft.ApiManagement/service/${apim.outputs.apimServiceName}/subscriptions/${apim.outputs.azureOpenAiApimSubscriptionName}/listSecrets?api-version=2024-05-01"' : ''

@description('Storage Account の名前')
output storageAccountName string = core.outputs.storageAccountName

@description('Key Vault の名前')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('Key Vault の URI')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('手動で再デプロイする場合のコマンド')
output deployCommand string = 'cd python && func azure functionapp publish ${functionApp.outputs.functionAppName}'
