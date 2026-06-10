using './main.bicep'

// 本番値は main.local.bicepparam.example をコピーして main.local.bicepparam を作成し、
// デプロイ時に --parameters main.local.bicepparam を指定して上書きしてください。

param prefix = 'aksdemo'
param nodeCount = 2
param nodeVmSize = 'Standard_DS2_v2'
param pgAdminUser = 'pgadmin'
param pgVersion = '16'

// プレースホルダ：実際のパスワードは main.local.bicepparam で上書きするか、
// CLI の --parameters pgAdminPassword='...' で渡してください。
param pgAdminPassword = 'ChangeMe_Strong#Pass1'
