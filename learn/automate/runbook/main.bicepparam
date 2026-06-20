using './main.bicep'

// 既定値で問題ない場合はこのまま。実験時は justfile のレシピが --parameters で
// 上書きする (例: just schedule が deploySchedule=true / scheduleTimeZone を渡す)。

param prefix = 'rbvm'
param targetVMName = 'vm-rbtarget'
param defaultAction = 'Stop'
