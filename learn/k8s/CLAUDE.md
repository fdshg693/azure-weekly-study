# k8s（AKS）トピック — ユーザーのレベル感と次プロジェクトの目安

このトピックは **AKS（Azure Kubernetes Service）** を主役に、`learn/k8s/{name}/` の各プロジェクトで
段階的に学ぶ。共通方針はリポジトリ全体と同じ「**一般概念／最小構成 → 実装 → 設定を出し入れして因果を
確かめる**」「**構築・実行はユーザー自身、AI は Azure 上で実行しない**」。
次プロジェクトの設計の目安は [PLAN.md](./PLAN.md) を参照（ロードマップの正本）。

## プロジェクト一覧

### `simple` — AKS が主役の最小構成アプリ
Bicep で ACR / AKS（application routing addon）/ AcrPull ロール / PostgreSQL をまとめて作り、
Deployment（API / front）・ClusterIP Service・単一 Ingress（`/api`→API・`/`→front）・HPA・
Secret（`db-conn` を `envFrom`）・probe（`/healthz`）を一周。`self-heal-demo` で Pod 削除→自己修復を観察。

### `config-rollout` — ConfigMap とローリングアップデートが主役（PLAN Step 1）
`simple` のインフラを**流用**（新規 Bicep なし）し、`config-rollout` 名前空間に最小アプリを置く。
- **ConfigMap（非機密）vs Secret（機密）** の使い分けを `envFrom` で体感。`envFrom` の env は Pod 起動時固定
  → ConfigMap 変更は `rollout restart` するまで反映されない、という因果を実験。
- 1 ソースから `ARG`（`APP_VERSION` / `BREAK_HEALTH`）で `:v1` / `:v2` / `:v2-bad` を作り分け、
  **RollingUpdate（maxSurge/maxUnavailable）** と `rollout status/history/undo` を往復。
- `:v2-bad` の壊れた readiness probe で**ロールアウトが止まり古い Pod が生き残る**ことを確認。
- namespace による `simple` との隔離、`requests.cpu` と HPA 発火タイミングの関係（補足実験）。

### `workload-identity` — Workload Identity による DB パスワードレス接続が主役（PLAN Step 2）
`simple` のインフラを**流用**し、`db-conn` Secret のパスワード接続を**キーレス化**する。
- **UAMI + Federated Identity Credential** を新規 Bicep で作り（`main.bicep` はこの 2 つだけ）、
  AKS の OIDC 有効化・PG の Entra 認証有効化・PG 管理者の付け外しは az スクリプトに分離。
- 三者の紐付け（**ServiceAccount ↔ UAMI ↔ PostgreSQL**）を体感。SA 注釈 `client-id` と
  Pod ラベル `azure.workload.identity/use:"true"` で webhook がトークン交換用 env を注入。
- `app.py` は `DefaultAzureCredential` で**毎回トークンを発行**し DB の `password` に渡す（`PGPASSWORD` env は無い）。
- **因果実験**: `role-off`/`role-on` で PG の Entra 管理者を付け外し → `db.connected` が false⇄true に変化。
  「認証（トークン取得）と認可（DB ログイン許可）は別」を体感（auth トピックの RBAC を k8s に接続）。

### `helm-kustomize` — マニフェストのテンプレート化と環境差分が主役（PLAN Step 3）
`simple` のインフラを**流用**（新規 Bicep なし・**DB も使わない**）し、同じベースのマニフェストを
**Kustomize の overlay** と **Helm の values** の**両方**で `dev` / `prod` に出し分ける（同じ問題を 2 ツールで解く比較）。
- `__ACR_LOGIN_SERVER__` の sed を卒業し、Kustomize の **images transformer**（`kustomize edit set image`）と
  Helm の **`--set image.registry`** で実イメージを構造的に注入。
- **Kustomize**: base + overlay、strategic merge patch / JSON6902 patch、images・replicas・namespace transformer。
- **Helm**: chart / Chart.yaml、values 重ね合わせ（`-f`）、Go テンプレート（`{{ if }}` で prod だけ HPA 生成）、
  `_helpers.tpl`、**release**（`helm list`/`status`/`get values`/`rollback`）と `upgrade --install`。
- 環境差分は replicas（1↔3）・resources・HPA 有無・設定（APP_ENV/APP_MESSAGE）・Ingress host・namespace に出す
  （**イメージは 1 種類のみ**で「同じ成果物を構成し分ける」に集中）。
- **因果実験**: `kubectl kustomize` / `helm template` の**レンダリング差分**で「同じベース→差分だけで 2 環境」を可視化。
  `kubectl diff -k` で宣言→差分→適用。ブラウザ観察は `just pf dev/prod`（front が `/api` をプロキシ）で別ポートに並べる。

### `observability` — 可観測性（Container Insights / マネージド Prometheus + Grafana）が主役（PLAN Step 4）
`simple` のインフラを**流用**（新規 Bicep なし・**DB も Ingress も使わない**）し、`observability` 名前空間に
「負荷つまみ付きの最小 API」を置いて、**動いているものを監視で観察する**ことに集中する。
- **監視の貯め先の地図**: ログ/コンテナ状態/再起動 → **Log Analytics**（Container Insights）、
  時系列メトリクス → **Azure Monitor ワークスペース**（**マネージド Prometheus**、PromQL）。表示は **Managed Grafana**。
- 監視の有効化は**既存クラスタへの後付け**なので Bicep 再デプロイではなく az スクリプト
  （`az aks enable-addons --addons monitoring` / `az aks update --enable-azure-monitor-metrics --grafana-resource-id` / `az grafana create`）。
- **2 段階に分割**: Container Insights（安価な第一歩）→ マネージド Prometheus + Grafana（任意・**Grafana はインスタンス課金**、`monitoring-off` で片付け）。
- アプリは監視グラフを動かす「負荷つまみ」だけを持つ: `/work`(同期 CPU で HPA 発火)・`/burn`(単一 Pod を焼く)・`/crash`(再起動を起こす)。
- **因果実験**: `just load` で CPU↑→ `watch-hpa` でレプリカ 2→10 のスケールアウトを見つつ、同じ時間軸の CPU グラフを Insights/Grafana で確認し、
  **HPA のスケール判断の根拠（観測した CPU 上昇）を裏側から理解**。`crash`/`self-heal` で再起動回数がダッシュボードに増えるのも観察。

## 学習済みの概念

クラスタ調達（Bicep で ACR/AKS/PostgreSQL）、AcrPull による imagePullSecret レス pull、
Deployment / ReplicaSet / 自己修復、ClusterIP Service、application routing addon（マネージド NGINX）の
単一 Ingress 集約、HPA（CPU 使用率）、Secret の `envFrom` 注入、probe（liveness/readiness）、
**ConfigMap、RollingUpdate 戦略、rollout undo/history/restart、namespace、build-arg によるイメージ作り分け、
readiness がロールアウトを止める仕組み**、
**Workload Identity（OIDC issuer / UAMI / Federated Identity Credential / SA との紐付け）、
PostgreSQL の Microsoft Entra 認証によるパスワードレス接続、認証と認可の分離**、
**マニフェストのテンプレート化（Kustomize の base/overlay・各種 transformer・patch、Helm の chart/values/テンプレート/release）、
dev/prod の環境差分の出し分け、レンダリング差分（`kubectl kustomize`/`helm template`）による可視化**、
**可観測性（Container Insights=Log Analytics・マネージド Prometheus=Azure Monitor ワークスペース+PromQL・Managed Grafana、
監視の貯め先の地図、HPA のスケール判断をメトリクスの時系列から裏付ける）**。

## まだ触れていない主要概念（PLAN の続き）

- **永続化**: PVC / StatefulSet、Azure Disk / Azure Files CSI。
- **HTTPS/証明書**: Ingress TLS、cert-manager（PLAN Step 5）。
- **イベント駆動スケール**: KEDA、クラスタオートスケーラー。
- **k8s 内認可・隔離**: RBAC、NetworkPolicy。
- **CI/CD・GitOps**、**Gateway API への移行**。
