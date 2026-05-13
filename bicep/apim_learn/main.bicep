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

@description('Python ランタイムのバージョン')
@allowed(['3.9', '3.10', '3.11', '3.12', '3.13'])
param pythonVersion string = '3.11'

@description('App Service Plan の SKU。Identity-based AzureWebJobsStorage は Premium (EP*) 以上が必要なため、デフォルトは EP1。Y1 (Consumption) は未対応。')
@allowed(['Y1', 'EP1', 'EP2', 'EP3', 'B1'])
param servicePlanSku string = 'EP1'

@description('API Management の SKU')
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
@description('APIM と Function App 間で共有するバックエンド認証シークレット。Key Vault に格納される。未指定時はデプロイ時に自動生成（newGuid）。本番では bicepparam の az.getSecret() で受け渡しを推奨。')
param backendSharedSecret string = newGuid()

@description('Azure OpenAI を新規作成し、APIM 配下の別 API として公開するか')
param enableAzureOpenAiApi bool = false

@description('Azure OpenAI 関連の設定をまとめたオブジェクト。enableAzureOpenAiApi=true のときのみ使用される。')
param azureOpenAi object = {
  location: location
  deploymentName: 'gpt-4o-mini'
  modelName: 'gpt-4o-mini'
  modelVersion: ''
  deploymentSkuName: 'Standard'
  deploymentCapacity: 10
  versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
}

// ============================================================================
// 名前とコード定義
// ============================================================================
var resourceNames = {
  functionApp: 'func-${prefix}-${suffix}'
  apim: 'apim-${prefix}-${take(suffix, 8)}'
  azureOpenAi: 'aoai-${prefix}-${take(suffix, 8)}'
  // Key Vault 名は 3-24 文字、英数字とハイフンのみ
  keyVault: take('kv-${prefix}-${take(suffix, 8)}', 24)
}

// Function コード一式（zip deploy 用）
var functionCode = {
  source: loadTextContent('python/function_app.py')
  hostJson: loadTextContent('python/host.json')
  requirements: loadTextContent('python/requirements.txt')
  deployScript: loadTextContent('scripts/deploy_function_code.py')
}
var functionCodeHash = uniqueString(functionCode.source, functionCode.hostJson, functionCode.requirements, pythonVersion)

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

// Key Vault は Function App / APIM より先に作成しておく（URI を双方へ渡すため）
module keyVault './modules/key-vault.bicep' = {
  name: 'keyVaultResources'
  params: {
    location: location
    keyVaultName: resourceNames.keyVault
    backendSharedSecret: backendSharedSecret
    tags: tags
  }
}

module azureOpenAiModule './modules/azure-openai.bicep' = {
  name: 'azureOpenAiResources'
  params: {
    location: azureOpenAi.location
    azureOpenAiAccountName: resourceNames.azureOpenAi
    enableAzureOpenAiApi: enableAzureOpenAiApi
    azureOpenAiDeploymentName: azureOpenAi.deploymentName
    azureOpenAiModelName: azureOpenAi.modelName
    azureOpenAiModelVersion: azureOpenAi.modelVersion
    azureOpenAiDeploymentSkuName: azureOpenAi.deploymentSkuName
    azureOpenAiDeploymentCapacity: azureOpenAi.deploymentCapacity
    azureOpenAiVersionUpgradeOption: azureOpenAi.versionUpgradeOption
    tags: tags
  }
}

module functionApp './modules/function-app.bicep' = {
  name: 'functionAppResources'
  params: {
    location: location
    functionAppName: resourceNames.functionApp
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
    apimServiceName: resourceNames.apim
    apimSkuName: apimSkuName
    apimPublisherName: apimPublisherName
    apimPublisherEmail: apimPublisherEmail
    functionDefaultHostName: functionApp.outputs.functionDefaultHostName
    tags: tags
    backendSecretUri: keyVault.outputs.backendSecretUri
    enableAzureOpenAiApi: enableAzureOpenAiApi
    azureOpenAiEndpoint: azureOpenAiModule.outputs.azureOpenAiEndpoint
  }
}

// ロール割り当ては Function App と APIM の MI が確定してから一括で行う
module roleAssignments './modules/role-assignments.bicep' = {
  name: 'roleAssignments'
  params: {
    storageAccountName: core.outputs.storageAccountName
    keyVaultName: keyVault.outputs.keyVaultName
    functionAppPrincipalId: functionApp.outputs.functionAppPrincipalId
    apimPrincipalId: apim.outputs.apimPrincipalId
    enableAzureOpenAiApi: enableAzureOpenAiApi
    azureOpenAiAccountName: azureOpenAiModule.outputs.azureOpenAiAccountName
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
    functionAppSource: functionCode.source
    hostJsonContent: functionCode.hostJson
    requirementsTxtContent: functionCode.requirements
    deployPythonScript: functionCode.deployScript
    functionCodeHash: functionCodeHash
  }
  dependsOn: [
    roleAssignments
  ]
}

// ============================================================================
// 出力
// ============================================================================

// APIM サブスクリプションキー取得用の az CLI コマンドテンプレート
var listSecretsUriBase = '${environment().resourceManager}subscriptions/$(az account show --query id -o tsv)/resourceGroups/${resourceGroup().name}/providers/Microsoft.ApiManagement/service/${apim.outputs.apimServiceName}/subscriptions'
var apiKeyCommandTemplate = 'az rest --method post --uri "${listSecretsUriBase}/{0}/listSecrets?api-version=2024-05-01"'

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
output azureOpenAiAccountName string = azureOpenAiModule.outputs.azureOpenAiAccountName

@description('Azure OpenAI リソースのエンドポイント。未有効時は空文字')
output azureOpenAiEndpoint string = azureOpenAiModule.outputs.azureOpenAiEndpoint

@description('Azure OpenAI モデルデプロイ名。未有効時は空文字')
output azureOpenAiDeploymentName string = azureOpenAiModule.outputs.azureOpenAiDeploymentName

@description('利用者が送る API キーのヘッダー名')
output apiKeyHeaderName string = apim.outputs.apiKeyHeaderName

@description('APIM サブスクリプションキーを取得する Azure CLI コマンド')
output apiKeyCommand string = replace(apiKeyCommandTemplate, '{0}', apim.outputs.apimSubscriptionName)

@description('Azure OpenAI 用 APIM サブスクリプションキーを取得する Azure CLI コマンド。未有効時は空文字')
output azureOpenAiApiKeyCommand string = enableAzureOpenAiApi ? replace(apiKeyCommandTemplate, '{0}', apim.outputs.azureOpenAiApimSubscriptionName) : ''

@description('Storage Account の名前')
output storageAccountName string = core.outputs.storageAccountName

@description('Key Vault の名前')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('Key Vault の URI')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('手動で再デプロイする場合のコマンド')
output deployCommand string = 'cd python && func azure functionapp publish ${functionApp.outputs.functionAppName}'
