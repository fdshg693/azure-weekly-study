using './main.bicep'

// 既定値で問題ない場合はこのまま。実験時は justfile のレシピが
// --parameters でここの値を上書きする (例: cronExpression / failJob)。

param prefix = 'cajob'
param cronExpression = '*/5 * * * *'
param jobMessage = 'hello from container apps job'
