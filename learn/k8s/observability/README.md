# observability — 可観測性 (Container Insights / マネージド Prometheus + Grafana) が主役

k8s 学習プラン（[../PLAN.md](../PLAN.md)）の **Step 4**。
`simple` で作った AKS / ACR を**そのまま流用**し（新しい Bicep は無い）、同じクラスタの
`observability` 名前空間に「負荷を掛けられる小さな API」を置く。そのうえで AKS の**監視を有効化**し、
**CPU/メモリ・Pod の再起動・HPA のスケール判断**を**ダッシュボードの裏側（時系列メトリクス）**から理解する。

> このプロジェクトでは「アプリを作る」ことより「**動いているものを観察する**」ことが主役。
> アプリ側は監視グラフを意図的に動かすための「負荷つまみ」(`/work` `/burn` `/crash`) を持つだけ。

## 2 段階の監視（安い方から）

| 段階 | 何が見えるか | コスト感 | 有効化 |
|---|---|---|---|
| **Container Insights**（Log Analytics） | コンテナの CPU/メモリ、Pod/ノードの状態、再起動、ログ。Portal の Insights ブレード | 取り込み量課金（小規模なら軽い） | `just monitoring-insights` |
| **マネージド Prometheus + Managed Grafana** | 時系列メトリクスを PromQL で、Grafana の K8s 標準ダッシュボードで | **Grafana はインスタンス課金**＋メトリクス取り込み | `just monitoring-on` |

まず Container Insights だけで体験し、Grafana の表現力を見たくなったら `monitoring-on` を足す、という順番を推奨。
**Grafana を有効化したら、学習後は必ず `just monitoring-off` で止める/消すこと**（課金停止）。

## 前提

- `simple` 側のインフラが**デプロイ済み**であること（`learn/k8s/simple` で `just group-create` → `just deploy-local` まで）。
  - 既定のリソースグループ `rg-aks-demo` / デプロイ名 `main` の出力（ACR 名・ACR ログインサーバ・AKS 名）をこのプロジェクトが読む。
- `az login` 済み、`kubectl` あり（無ければ `simple` の `just install-kubectl`）。
- このプロジェクトは **Ingress も DB も使わない**ので、`simple` のアプリ層を止める必要はない（外部 IP を共有しない）。
  ただし小さなクラスタなので、CPU 実験中は他の重いワークロードを止めておくと観察しやすい。

## 構成

```
observability/
├─ api/                       # 負荷つまみ付きの Flask API (監視グラフを動かす観察対象)
│  ├─ app.py                 # /work(同期CPU) /burn(単一Pod) /crash(再起動) /healthz
│  ├─ Dockerfile            # observ/api:v1 を 1 種類だけ
│  └─ requirements.txt
├─ manifests/
│  ├─ namespace.yaml        # observability 名前空間 (simple と隔離)
│  ├─ deployment.yaml       # requests/limits を明示 (HPA の分母・グラフの基準)
│  ├─ service.yaml          # ClusterIP (負荷を全 Pod に分散)
│  └─ hpa.yaml              # CPU 50% で 2→10
├─ scripts/                   # az の多段処理は justfile に埋めず PowerShell に分離
│  ├─ lib.ps1               # simple のデプロイ出力 (ACR/AKS) を取得
│  ├─ credentials.ps1       # az aks get-credentials
│  ├─ acr-build.ps1         # observ/api:v1 をビルド
│  ├─ apply.ps1             # image を置換してマニフェスト適用
│  ├─ enable-insights.ps1   # Container Insights を有効化
│  ├─ enable-prometheus.ps1 # マネージド Prometheus + Grafana を有効化 (★課金)
│  ├─ links.ps1             # Portal / Grafana への入口を表示
│  ├─ load.ps1              # /work を多重に叩いて HPA を発火させる
│  └─ disable.ps1           # 監視を片付けて課金停止
└─ justfile                   # 上記を呼ぶだけの薄い入口
```

## デプロイ手順

```pwsh
# simple のインフラが既にある前提。まず観察対象アプリをビルド & 適用。
just acr-build
just k8s-up                                  # credentials → apply (namespace/Deployment/Service/HPA)
just status                                  # Pod / Service / HPA を確認

# 監視を有効化 (まずは安い Container Insights から)
just monitoring-insights                     # Log Analytics ベースの Insights を有効化

# (任意) Grafana の表現力も見たい場合 — ★課金あり
just monitoring-on                           # マネージド Prometheus + Managed Grafana を作成・紐付け
just links                                   # Portal リンク / Grafana URL を表示
```

> 監視メトリクスは有効化から**数分**遅れて出始める。すぐにグラフが空でも慌てないこと。

## 動作確認と「因果を確かめる」実験

### 実験 A — 負荷をかけて HPA のスケールアウトを「裏側」から見る

```pwsh
# ターミナル1: HPA の判断 (現在 CPU% / レプリカ数) を実況
just watch-hpa
# ターミナル2: Pod の増減を実況
just watch-pods
# ターミナル3: /work を多重に叩いて CPU を上げる (Ctrl-C で停止)
just load            # 既定 Concurrency=20, ms=50。足りなければ just load 40 100
```

数十秒で CPU% が `averageUtilization=50` を超え、レプリカが 2→…→最大 10 へ増えるのが `watch-hpa` で見える。
同じ瞬間を **Container Insights / Grafana の CPU グラフ**でも見ると、「HPA が増やしたのは**この CPU 上昇**を見たから」と
**スケール判断の根拠**が腹落ちする。負荷を止めると（クールダウン後に）レプリカが縮むのも観察できる。

`hpa.yaml` の `averageUtilization` や `deployment.yaml` の `requests.cpu` を変えて `just apply` すると、
同じ負荷でも発火タイミングが変わる（requests を下げると分母が小さくなり早く発火）。

### 実験 B — 特定 1 Pod だけ CPU を焼いて、Pod ごとの線を見分ける

```pwsh
just burn-one 60     # deploy/api のうち 1 Pod を 60 秒バックグラウンドで焼く
```

Grafana の「Pod 単位」ダッシュボードで、**焼いた Pod の CPU 線だけが跳ね**、他は平坦なのが見える。
「メトリクスは Pod 粒度で取れている」ことを体感する。

### 実験 C — Pod を落として「再起動」をダッシュボードで観測

```pwsh
just crash           # 1 Pod の /crash を叩いてプロセスを落とす
just status          # RESTARTS が増えているのを確認
```

liveness probe 失敗 → kubelet がコンテナを再起動 → Container Insights の「Containers」や Grafana の
restart 系メトリクスで**再起動回数が増える**のが見える。`self-heal` でも同様に Pod 消失→再作成を観察できる。

```pwsh
just self-heal       # Pod を 1 つ手で削除 → ReplicaSet が再作成
```

## 後片付け

```pwsh
just monitoring-off  # ★Grafana 削除＋監視無効化 (課金停止)。Grafana を有効化したら必ず実行
just destroy         # observability 名前空間だけ削除 (simple のクラスタ/インフラは残る)
```

`simple` のインフラまで消したい場合は `learn/k8s/simple` 側で `just destroy`。

## 設計上の割り切り

- インフラは `simple` を流用し、新規 Bicep は持たない（PLAN の「既存 AKS をそのまま使う」方針）。
  監視の有効化は**既存クラスタへの後付け**なので、Bicep の再デプロイではなく **az スクリプト**で行う
  （`workload-identity` で az に分離したのと同じ判断）。
- 監視は **Container Insights（安い第一歩）→ マネージド Prometheus + Grafana（任意・課金）** の 2 段階に分け、
  学習者がコストを見ながら踏み込めるようにした。
- アプリは 1 種類のイメージ・Ingress/DB 無し。**「観察対象を動かす」最小限**に絞り、監視そのものに集中する。
