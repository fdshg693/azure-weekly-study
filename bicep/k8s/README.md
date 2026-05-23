# k8s — AKS が主役の最小構成アプリ (Bicep + Justfile 実装)

記事 [`aks_app_build.md`](aks_app_build.md) を、Bicep（Azure インフラ）と Justfile（オーケストレーション）で
動く形に落としたプロジェクト。記事が `az` コマンド列で組んでいたインフラを宣言的な Bicep に置き換え、
K8s マニフェスト本体は `manifests/` に分離して `kubectl` で適用する。

## 構成

```
k8s/
├─ main.bicep                 # ACR / AKS / AcrPull ロール / PostgreSQL を束ねる
├─ main.bicepparam            # 既定パラメータ (パスワードはプレースホルダ)
├─ main.local.bicepparam.example  # 本番値用テンプレート (コピーして使う)
├─ modules/
│  ├─ acr.bicep              # Azure Container Registry (Basic)
│  ├─ aks.bicep             # AKS + application routing addon (マネージド NGINX)
│  ├─ acr-role.bicep        # 記事の --attach-acr 相当: kubelet ID に AcrPull
│  └─ postgres.bicep        # PostgreSQL フレキシブル + Azure 内許可の FW ルール
├─ manifests/                # 記事ステップ4〜6 の YAML (主役パート)
│  ├─ api-deployment.yaml   # image は __ACR_LOGIN_SERVER__ を apply 時に置換
│  ├─ front-deployment.yaml
│  ├─ services.yaml         # api / front の ClusterIP
│  ├─ ingress.yaml          # /api→api, /→front を 1 つの玄関に集約
│  └─ hpa.yaml              # API の CPU オートスケール
├─ api/                       # サンプル API (Flask + psycopg, /healthz と /api)
│  ├─ app.py
│  ├─ requirements.txt
│  └─ Dockerfile            # 8080 で待ち受け
├─ front/                     # サンプル front (nginx 静的ページ)
│  ├─ index.html            # /api を叩いて疎通確認するボタン付き
│  └─ Dockerfile            # 80 で待ち受け
└─ justfile                   # 一連の手順をレシピ化
```

## 記事との対応

| 記事の手順 (az / kubectl) | このプロジェクトでの実現 |
|---|---|
| `az acr create` | `modules/acr.bicep` |
| `az aks create --enable-app-routing` | `modules/aks.bicep` の `ingressProfile.webAppRouting` |
| `az aks create --attach-acr` | `modules/acr-role.bicep` (kubelet ID に AcrPull ロール) |
| `az postgres flexible-server create --public-access 0.0.0.0` | `modules/postgres.bicep` + FW ルール `0.0.0.0-0.0.0.0` |
| `az acr build ... ./api ./front` | `just acr-build` |
| `kubectl create secret generic db-conn ...` | `just secret-create` |
| `kubectl apply -f *.yaml` | `just apply`（`manifests/` を適用） |

## 前提

- Azure CLI (`az login` 済み)
- [`just`](https://github.com/casey/just)（任意。なくても下の「素の az/kubectl」で進められる）
- `kubectl`（無ければ `just install-kubectl` または `az aks install-cli`）
- Docker は不要（ビルドは `az acr build` がクラウド側で実行する）

## デプロイ手順（just を使う場合）

```pwsh
just init-local-param                       # main.local.bicepparam.example をコピー
# main.local.bicepparam を編集し pgAdminPassword を強固なパスワードに差し替える

just group-create                           # 既定: rg-aks-demo / japaneast
just deploy-local                           # ACR / AKS / AcrPull / PostgreSQL を作成
just acr-build                              # api/ front/ をクラウドビルド & プッシュ

# K8s 側 (認証情報取り込み → Secret → マニフェスト適用) をまとめて
just k8s-up rg-aks-demo "差し替えたパスワード"

just status                                 # Pod / Service / Ingress / HPA を確認
just ingress-ip                             # 外部 IP が出たらブラウザでアクセス
```

> `k8s-up` の代わりに `just credentials` → `just secret-create rg-aks-demo "<password>"` → `just apply` を個別に実行してもよい。

利用可能なレシピは `just`（引数なし）で一覧表示。

## 動作確認

- `just ingress-ip` で出た IP を `http://<IP>/` で開くと front のページが出る。
- ページの「GET /api」ボタンで Ingress 経由 `/api` → API Pod → PostgreSQL の疎通が JSON で見える
  （`db.connected: true` なら DB まで通っている）。
- `just self-heal-demo` で Pod を 1 つ消すと、すぐ新しい Pod が生まれて 2 つに戻る（自己修復）。

## 後片付け

```pwsh
just destroy        # az group delete --yes --no-wait（LB / IP もまとめて消える）
```

## 設計上の割り切り（記事と同じく POC 前提）

- PostgreSQL は `--public-access 0.0.0.0`（Azure 内サービスからのみ許可）。本番は VNet 統合 / Private Endpoint。
- DB 接続は Kubernetes Secret 方式。本番は Workload Identity（パスワードレス）が推奨（記事の発展章）。
- application routing addon（NGINX）は移行期。長期運用は Gateway API への移行計画を前提に。
- APIM / Redis / 監視・ログ / CI-CD は意図的に省略（K8s の役割を浮かび上がらせるため）。
