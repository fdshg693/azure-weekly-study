# k8s 学習プラン — `simple` の次に何をやるか

このファイルは k8s トピックの**次プロジェクトの設計の目安**。
方針はリポジトリ共通（[../CLAUDE.md](../CLAUDE.md)）どおり:
「**一般概念／最小構成 → 実装 → 設定を出し入れして因果を確かめる**」「**構築・実行はユーザー自身、AI は Azure 上で実行しない**」。

---

## 1. `simple` で到達済みのこと

| 領域 | 学べた内容 |
|---|---|
| クラスタ調達 | Bicep で ACR / AKS / AcrPull ロール / PostgreSQL をまとめて作る |
| ワークロード | Deployment（API / front の 2 つ）、ReplicaSet による自己修復 |
| ネットワーク | ClusterIP Service、application routing addon（マネージド NGINX）の単一 Ingress で `/api`→API・`/`→front を集約 |
| スケール | HPA（CPU 50% で 2→10） |
| 設定の受け渡し | Kubernetes Secret（`db-conn`）を `envFrom` で注入 |
| probe | `/healthz` を liveness/readiness に使う発想 |
| 運用体験 | `self-heal-demo` で Pod を消して復活を観察 |

## 2. まだ触れていない主要概念（次の候補）

- **設定とロールアウト**: ConfigMap、ローリングアップデート戦略・`rollout undo`、`resources.requests/limits`、namespace
- **キーレス化**: Workload Identity による DB パスワードレス接続（`simple` の「発展章」宿題）
- **永続化**: PVC / StatefulSet、Azure Disk / Azure Files CSI ドライバ
- **テンプレート化**: 今の `__ACR_LOGIN_SERVER__` 置換は応急処置 → Helm か Kustomize へ
- **HTTPS / 証明書**: Ingress の TLS、cert-manager、独自ドメイン
- **可観測性**: Container Insights（Azure Monitor）／マネージド Prometheus + Grafana
- **イベント駆動スケール**: KEDA、クラスタオートスケーラー（ノード増減）
- **k8s 内認可・隔離**: RBAC、NetworkPolicy
- **CI/CD**: GitHub Actions から `acr build` → `kubectl apply`／GitOps
- **Ingress の将来**: application routing addon → Gateway API への移行

## 3. 推奨ロードマップ（やさしい順）

各プロジェクトは `learn/k8s/{name}/` に置く想定。`simple` のクラスタ／Bicep を流用できる構成を優先し、
「**1 プロジェクト = 主役の概念 1〜2 個**」に絞る（`simple` の割り切り精神を継続）。

### Step 5 — `tls-domain`（HTTPS 化）
**主役**: Ingress の TLS と証明書自動化。
- cert-manager または Azure 側の証明書で `https://` を有効化。
- **因果を確かめる実験**: 証明書の更新・失効でブラウザ表示がどう変わるか。

### Step 6（発展）— `gateway-api` / `keda` / `gitops`
- application routing addon → **Gateway API** へ移行し、Ingress と Gateway API のリソースモデル差を比較（`simple` で予告した移行）。
- **KEDA** でキュー長など CPU 以外のメトリクスによるイベント駆動スケール。
- **GitOps**（Argo CD / Flux）または GitHub Actions で `apply` を自動化し、手動 `just apply` との違いを体感。

## 4. 進め方のメモ

- Step 1〜2 は `simple` の AKS / ACR / PostgreSQL をそのまま再利用できるので、新規プロジェクトでも Bicep は最小差分で済む。
- 各プロジェクトには共通構成（`README.md` / `KNOWLEDGE.md` / `justfile` または `Taskfile.yml`）を置く。`simple` 同様、複雑になったら justfile ではなく Taskfile を使う。
- トピックの習熟度は別途 `learn/k8s/CLAUDE.md`（未作成）に記録する想定。最初のプロジェクトを 1 つ追加したタイミングで作成するとよい。
