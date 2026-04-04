@description('Azure リソースをデプロイするリージョン')
param location string

@description('Function App のコードもあわせてデプロイするか')
param publishFunctionCode bool = true

@description('Function App 名')
param functionAppName string

@description('Function App の Python ソース')
param functionAppSource string

@description('host.json の内容')
param hostJsonContent string

@description('requirements.txt の内容')
param requirementsTxtContent string

@description('zip deploy 用 Python スクリプト')
param deployPythonScript string

@description('デプロイ更新判定用ハッシュ')
param functionCodeHash string

var publishingCredentials = list(resourceId('Microsoft.Web/sites/config', functionAppName, 'publishingcredentials'), '2023-12-01')

resource functionCodeDeployment 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (publishFunctionCode) {
  name: 'publish-function-code'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.59.0'
    cleanupPreference: 'OnSuccess'
    forceUpdateTag: functionCodeHash
    retentionInterval: 'PT1H'
    timeout: 'PT30M'
    environmentVariables: [
      {
        name: 'SCM_HOST'
        value: '${functionAppName}.scm.azurewebsites.net'
      }
      {
        name: 'FUNCTION_APP_PY'
        value: functionAppSource
      }
      {
        name: 'HOST_JSON'
        value: hostJsonContent
      }
      {
        name: 'REQUIREMENTS_TXT'
        value: requirementsTxtContent
      }
      {
        name: 'DEPLOY_PYTHON_SCRIPT'
        value: base64(deployPythonScript)
      }
      {
        name: 'PUBLISH_USER'
        secureValue: publishingCredentials.properties.publishingUserName
      }
      {
        name: 'PUBLISH_PASSWORD'
        secureValue: publishingCredentials.properties.publishingPassword
      }
    ]
    scriptContent: '''
python3 -c "import base64, os; exec(base64.b64decode(os.environ['DEPLOY_PYTHON_SCRIPT']).decode('utf-8'))"
'''
  }
}
