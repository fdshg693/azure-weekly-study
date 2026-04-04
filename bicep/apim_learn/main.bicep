// ============================================================================
// シンプルな CRUD Function App + APIM のデプロイ
// ============================================================================
// main.bicep はオーケストレーターとして振る舞い、実リソース定義は modules/ に分割する。
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

@description('App Service Plan の SKU（Y1: Consumption サーバーレス）')
@allowed(['Y1', 'EP1', 'EP2', 'EP3', 'B1'])
param servicePlanSku string = 'Y1'

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
@description('APIM と Function App 間で共有するバックエンド認証シークレット。未指定時はデプロイ時に自動生成されます')
param backendSharedSecret string = newGuid()

@description('既存の Azure OpenAI を APIM 配下の別 API として公開するか')
param enableAzureOpenAiApi bool = false

@description('既存 Azure OpenAI リソースのエンドポイント。末尾の / は付けずに指定してください。例: https://example.openai.azure.com')
param azureOpenAiEndpoint string = ''

@secure()
@description('既存 Azure OpenAI リソースの API キー')
param azureOpenAiApiKey string = ''

// ============================================================================
// 名前とコード定義
// ============================================================================
var functionAppName = 'func-${prefix}-${suffix}'
var apimServiceName = 'apim-${prefix}-${take(suffix, 8)}'
var functionAppSource = loadTextContent('python/function_app.py')
var hostJsonContent = loadTextContent('python/host.json')
var requirementsTxtContent = loadTextContent('python/requirements.txt')
var functionCodeHash = uniqueString(functionAppSource, hostJsonContent, requirementsTxtContent, pythonVersion)
var deployPythonScript = loadTextContent('scripts/deploy_function_code.py')

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

module functionApp './modules/function-app.bicep' = {
  name: 'functionAppResources'
  params: {
    location: location
    functionAppName: functionAppName
    servicePlanId: core.outputs.servicePlanId
    storageAccountName: core.outputs.storageAccountName
    pythonVersion: pythonVersion
    tags: tags
    backendSharedSecret: backendSharedSecret
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
    backendSharedSecret: backendSharedSecret
    enableAzureOpenAiApi: enableAzureOpenAiApi
    azureOpenAiEndpoint: azureOpenAiEndpoint
    azureOpenAiApiKey: azureOpenAiApiKey
  }
}

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

@description('利用者が送る API キーのヘッダー名')
output apiKeyHeaderName string = apim.outputs.apiKeyHeaderName

@description('APIM サブスクリプションキーを取得する Azure CLI コマンド')
output apiKeyCommand string = 'az rest --method post --uri "${environment().resourceManager}subscriptions/$(az account show --query id -o tsv)/resourceGroups/${resourceGroup().name}/providers/Microsoft.ApiManagement/service/${apim.outputs.apimServiceName}/subscriptions/${apim.outputs.apimSubscriptionName}/listSecrets?api-version=2024-05-01"'

@description('Azure OpenAI 用 APIM サブスクリプションキーを取得する Azure CLI コマンド。未有効時は空文字')
output azureOpenAiApiKeyCommand string = enableAzureOpenAiApi ? 'az rest --method post --uri "${environment().resourceManager}subscriptions/$(az account show --query id -o tsv)/resourceGroups/${resourceGroup().name}/providers/Microsoft.ApiManagement/service/${apim.outputs.apimServiceName}/subscriptions/${apim.outputs.azureOpenAiApimSubscriptionName}/listSecrets?api-version=2024-05-01"' : ''

@description('Storage Account の名前')
output storageAccountName string = core.outputs.storageAccountName

@description('手動で再デプロイする場合のコマンド')
output deployCommand string = 'cd python && func azure functionapp publish ${functionApp.outputs.functionAppName}'
