@description('Azure OpenAI をデプロイするリージョン')
param location string

@description('Azure OpenAI リソース名')
param azureOpenAiAccountName string

@description('Azure OpenAI のカスタムサブドメイン名。通常はリソース名と同じで問題ありません')
param azureOpenAiCustomSubdomain string = azureOpenAiAccountName

@description('Azure OpenAI を作成して APIM 配下へ公開するか')
param enableAzureOpenAiApi bool = false

@description('Azure OpenAI リソースの SKU。現在は Standard のみ想定')
@allowed(['S0'])
param azureOpenAiSkuName string = 'S0'

@description('Azure OpenAI のモデルデプロイ名')
param azureOpenAiDeploymentName string = 'gpt-4o-mini'

@description('Azure OpenAI にデプロイするモデル名')
param azureOpenAiModelName string = 'gpt-4o-mini'

@description('Azure OpenAI モデルのバージョン。空文字の場合は Azure の既定バージョンを利用します')
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

@description('Azure OpenAI モデルデプロイのサービスタイア')
@allowed(['Default', 'Priority'])
param azureOpenAiDeploymentServiceTier string = 'Default'

@description('リソースに適用するタグ')
param tags object = {}

var azureOpenAiModel = empty(azureOpenAiModelVersion)
  ? {
      format: 'OpenAI'
      name: azureOpenAiModelName
    }
  : {
      format: 'OpenAI'
      name: azureOpenAiModelName
      version: azureOpenAiModelVersion
    }

resource azureOpenAiAccount 'Microsoft.CognitiveServices/accounts@2025-12-01' = if (enableAzureOpenAiApi) {
  name: azureOpenAiAccountName
  location: location
  kind: 'OpenAI'
  sku: {
    name: azureOpenAiSkuName
  }
  properties: {
    customSubDomainName: azureOpenAiCustomSubdomain
    disableLocalAuth: false
    dynamicThrottlingEnabled: false
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: false
  }
  tags: tags
}

resource azureOpenAiDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-12-01' = if (enableAzureOpenAiApi) {
  parent: azureOpenAiAccount
  name: azureOpenAiDeploymentName
  sku: {
    name: azureOpenAiDeploymentSkuName
    capacity: azureOpenAiDeploymentCapacity
  }
  properties: {
    deploymentState: 'Running'
    model: azureOpenAiModel
    serviceTier: azureOpenAiDeploymentServiceTier
    versionUpgradeOption: azureOpenAiVersionUpgradeOption
  }
}

output azureOpenAiAccountName string = enableAzureOpenAiApi ? azureOpenAiAccount.name : ''
output azureOpenAiEndpoint string = enableAzureOpenAiApi ? 'https://${azureOpenAiAccount.name}.openai.azure.com' : ''
output azureOpenAiDeploymentName string = enableAzureOpenAiApi ? azureOpenAiDeployment.name : ''