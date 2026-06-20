# config-rollout — ConfigMap とローリングアップデートが主役

k8s 学習プラン（[../PLAN.md](../PLAN.md)）の **Step 1**。
`simple` で作った AKS / ACR / PostgreSQL を**そのまま流用**し（新しい Bicep は無い）、
同じクラスタの `config-rollout` 名前空間に最小のアプリを置いて、次の 2 つを体感する。

1. **設定の出どころ**: 非機密の挙動は **ConfigMap**、機密の DB 接続情報は **Secret**。同じ `envFrom` でも置き場を使い分ける。
2. **バージョンの入れ替え**: 1 つのソースから `:v1` / `:v2` / `:v2-bad` を作り、**ローリングアップデート**と **`rollout undo`** を往復する。

## 前提

- `simple` 側のインフラが**デプロイ済み**であること（`learn/k8s/simple` で `just group-create` → `just deploy-local` まで）。
  - 既定のリソースグループ `rg-aks-demo` / デプロイ名 `main` の出力（ACR 名・ACR ログインサーバ・PostgreSQL FQDN）をこのプロジェクトが読む。
- `az login` 済み、`kubectl` あり（無ければ `simple` の `just install-kubectl`）。
- PostgreSQL のパスワードは `simple` のデプロイ時に設定した値（`db-conn` Secret に再投入する）。
- **`simple` のアプリ層は止めておく**ことを推奨。`simple` と本プロジェクトは同じ単一 NGINX / 外部 IP を
  共有し、両方の Ingress（どちらも host 無し・`/` と `/api`）が衝突して `/api` がどちらに飛ぶか不定になる。
  小さなクラスタの CPU/メモリ取り合いも避けられる。インフラは残したまま `learn/k8s/simple` で
  `just app-down`（クラスタ/ACR/PostgreSQL は残る。`just destroy` はインフラごと消すので使わない）。

## 構成

```
config-rollout/
├─ api/                       # ConfigMap/Secret から env を読む Flask API
│  ├─ app.py                 # version / message / feature_greeting / db を返す
│  ├─ Dockerfile            # ARG APP_VERSION / BREAK_HEALTH を ENV に焼き込む
│  └─ requirements.txt
├─ front/                     # /api を叩いて version・message を表示する静的ページ
│  ├─ index.html            # 「1 秒ごと自動更新」でロールアウトを目視できる
│  └─ Dockerfile
├─ manifests/
│  ├─ namespace.yaml        # config-rollout 名前空間 (simple と隔離)
│  ├─ configmap.yaml        # app-config: APP_MESSAGE / FEATURE_GREETING (非機密)
│  ├─ api-deployment.yaml   # 主役。RollingUpdate 戦略 + Secret/ConfigMap の envFrom
│  ├─ front-deployment.yaml
│  ├─ services.yaml         # api / front の ClusterIP
│  ├─ ingress.yaml          # /api→api, /→front
│  └─ hpa.yaml              # API の CPU オートスケール (requests 実験に使う)
├─ scripts/                   # 複雑な処理は justfile に埋めず PowerShell に分離
│  ├─ lib.ps1               # simple のデプロイ出力 (ACR/AKS/PG) を取得する共通関数
│  ├─ credentials.ps1       # az aks get-credentials
│  ├─ acr-build.ps1         # v1/v2/v2-bad/front をビルド
│  ├─ secret-create.ps1     # db-conn Secret を作成
│  ├─ apply.ps1             # image を置換してマニフェスト適用
│  ├─ rollout.ps1           # set image でタグ切り替え
│  └─ set-config.ps1        # ConfigMap の 1 キーを patch
└─ justfile                   # 上記を呼ぶだけの薄い入口 (単一 kubectl 系はインライン)
```

## デプロイ手順

```pwsh
# simple のインフラが既にある前提。まずイメージを simple の ACR にビルド (v1/v2/v2-bad/front)。
just acr-build

# 認証情報取り込み → Secret(db-conn)+namespace 作成 → マニフェスト適用 をまとめて。
# パスワードは simple のデプロイ時と同じ値を渡す。
just k8s-up rg-aks-demo "差し替えたパスワード"

just status                                 # Pod / Service / Ingress / HPA / ConfigMap を確認
just ingress-ip                             # 外部 IP が出たらブラウザでアクセス
```

> `k8s-up` の代わりに `just credentials` → `just secret-create rg-aks-demo "<password>"` → `just apply` を個別に実行してもよい。

ブラウザで `http://<IP>/` を開き、「1 秒ごと自動更新」にチェックを入れておくと、以降の実験で
`version` と `message` が切り替わる様子をリアルタイムに観察できる。

## 動作確認と「因果を確かめる」実験

### 実験 A — ConfigMap（非機密）と「反映には Pod 入れ替えが要る」こと

```pwsh
just set-message "メッセージを変えてみた"      # ConfigMap を書き換える
just status                                   # ← /api の message はまだ古いまま！
just config-reload                            # rollout restart で Pod を入れ替える
# → ここで初めて message が新しくなる
```

学び: `envFrom` で渡した env は **Pod 起動時に固定**される。ConfigMap を変えても自動では反映されず、
`kubectl rollout restart` で Pod を作り直して初めて反映される。

特徴フラグも同様に試せる:

```pwsh
just set-feature on    # FEATURE_GREETING=on
just config-reload     # /api に greeting フィールドが増える
```

機密との対比: DB 接続情報は **Secret(db-conn)** にあり、ConfigMap には入れない。`/api` の `db.connected: true`
は Secret 由来の値で `simple` の PostgreSQL に到達できていることを示す。

### 実験 B — ローリングアップデート（v1 → v2）

```pwsh
# 別ターミナルで実況を出しておくと入れ替わりが見える
just watch

# v2 へ更新 (maxUnavailable=1 / maxSurge=1 で少しずつ入れ替わる)
just rollout v2
just rollout-status        # 完了を待つ
```

学び: 古い Pod を一気に消さず、`maxSurge`（余分に立てる上限）と `maxUnavailable`（同時に欠けてよい上限）の
範囲で新旧が入れ替わる。`/api` の `version` が `v1`→`v2` に変わり、`new_in_v2` フィールドが増える。

`manifests/api-deployment.yaml` の `maxUnavailable` / `maxSurge` を変えて `just apply` → `just rollout v1`/`v2` を
往復すると、入れ替わり方（同時に何個動くか）が変化するのを比較できる。

### 実験 C — 壊れた v2 で readiness が止め、ロールバックで復旧

```pwsh
just rollout v2-bad        # /healthz が 500 を返すイメージ
just rollout-status        # ← 新 Pod が Ready にならず timeout で止まる
just status                # 古い v2(またはv1) Pod が生き残り、無停止が保たれている
just rollout-history       # 改訂の履歴
just rollout-undo          # 直前の正常版へ戻す → Ready に戻る
```

学び: readiness probe が新 Pod を Ready にしない限りロールアウトは前に進まない。
だから**壊れた版を出しても古い Pod が生き続け**、サービスは落ちない。`rollout undo` で安全に戻せる。

### 実験 D（任意）— resources.requests と HPA の発火タイミング

```pwsh
just load                  # 一時 Pod から /api を叩き続けて負荷をかける (Ctrl-C で停止)
# 別ターミナルで
kubectl get hpa -n config-rollout -w
```

`hpa.yaml` の `averageUtilization=50` は **`resources.requests.cpu` に対する割合**。
`api-deployment.yaml` の `requests.cpu` を下げて `just apply` すると、同じ負荷でも HPA が早く発火する
（分母が小さくなるため）ことを観察できる。

## 後片付け

```pwsh
just destroy        # config-rollout 名前空間だけ削除 (simple のクラスタ/インフラは残る)
```

`simple` のインフラまで消したい場合は `learn/k8s/simple` 側で `just destroy`。

## 設計上の割り切り

- インフラは `simple` を流用し、新規 Bicep は持たない（PLAN の「既存 AKS をそのまま使う」方針）。
- `:v2` と `:v1` の差は ARG（`APP_VERSION`）で焼き込んだ文字列＋応答の 1 フィールドのみ。ロールアウトの観察に集中するための割り切り。
- ConfigMap の自動リロード（`reloader` 等）は導入せず、あえて手動 `rollout restart` で「反映には Pod 入れ替えが要る」因果を体感する。
