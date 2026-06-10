using './main.bicep'

// すべて既定値で動く。リージョンやプレフィックスを変えたいときだけ上書きする。
param prefix = 'amldemo'

// 既定では resourceGroup().location を使う。明示したい場合は下を有効化。
// param location = 'japaneast'
