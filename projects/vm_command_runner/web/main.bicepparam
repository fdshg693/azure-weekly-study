using './main.bicep'

// 共通設定 (リポジトリに commit されてよい値)
param prefix = 'vmcmdweb'
param appServicePlanSku = 'B1'
param nodeVersion = '20-lts'

// 機密 / 環境固有のパラメータは main.local.bicepparam で上書きする
