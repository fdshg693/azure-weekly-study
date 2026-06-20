# 一時 Pod から /work を多重に叩き続け、Service 経由で全 Pod に負荷を分散する。
# 平均 CPU が requests の 50% を超えると HPA がスケールアウトする。
# Ctrl-C で抜けると一時 Pod は自動削除される (--rm)。
param(
    [int]$Concurrency = 20,   # 同時に走らせる無限ループ数
    [int]$Ms = 50             # 1 リクエストあたり CPU を焼くミリ秒
)

# busybox の中で並列ループを起動する小さなシェル。
# 各ループが Service 'api' の /work?ms=... を叩き続ける。
$inner = "i=0; while [ `$i -lt $Concurrency ]; do (while true; do wget -q -O- 'http://api/work?ms=$Ms' >/dev/null 2>&1; done) & i=`$((i+1)); done; echo \"started $Concurrency loops (ms=$Ms). Ctrl-C で停止\"; wait"

Write-Host "負荷生成 Pod を起動します (Concurrency=$Concurrency, Ms=$Ms)。別ターミナルで 'just watch-hpa' を見ながらどうぞ。" -ForegroundColor Cyan
kubectl run loadgen -n observability --image=busybox --restart=Never --rm -i --tty -- /bin/sh -c $inner
