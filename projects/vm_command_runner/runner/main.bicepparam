using './main.bicep'

// 本番値は main.local.bicepparam.example をコピーして main.local.bicepparam を作成し、
// デプロイ時に --parameters main.local.bicepparam を指定して上書きしてください。

param prefix = 'vmcmd'
param pythonVersion = '3.11'
param servicePlanSku = 'EP1'
param vmSize = 'Standard_B1s'
param vmAdminUsername = 'azureuser'
param idleMinutesBeforeStop = 10

// プレースホルダ：実際の SSH 公開鍵は main.local.bicepparam で上書きするか、
// CLI の --parameters vmAdminSshPublicKey="ssh-rsa AAAA..." で渡してください。
param vmAdminSshPublicKey = 'ssh-rsa AAAAB3NzaC1yc2E_PLACEHOLDER_REPLACE_ME'
