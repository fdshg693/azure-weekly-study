using './main.bicep'

// プレフィックスだけ固定。suffix はリソースグループから自動生成、location は RG に従う。
param prefix = 'msgapp'
