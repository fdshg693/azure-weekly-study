using './main.bicep'

// 既定値で十分なものは Bicep 側の default に任せ、ここでは触りどころだけ置く。
param prefix = 'reg'
param acrSku = 'Basic'

// 既定はキーレス (admin user 無効)。
// admin user の対比実験は Bicep を編集せず `task admin-on` / `task admin-off` で出し入れする。
param adminUserEnabled = false
