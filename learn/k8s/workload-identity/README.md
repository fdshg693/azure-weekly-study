# workload-identity — Workload Identity による DB パスワードレス接続が主役

k8s 学習プラン（[../PLAN.md](../PLAN.md)）の **Step 2**（`simple` の「発展章」宿題の回収）。
`simple` で作った AKS / ACR / PostgreSQL を**そのまま流用**し、これまで Secret(`db-conn`) の
**パスワード**で行っていた DB 接続を、**パスワードを一切持たない**方式へ置き換える。

中心テーマは **キーレス化**:

- Pod は ServiceAccount のトークンを、**User-Assigned Managed Identity (UAMI)** のトークンに
  「交換」して Microsoft Entra のアクセストークンを得る。
- そのトークンを **DB ログインのパスワード代わり**にして PostgreSQL に接続する。
- コードにも env にもシークレットが無い（`PGPASSWORD` は存在しない）。

紐付けの三者関係（ここが本プロジェクトの肝）:

```
ServiceAccount(pg-accessor)  ──FIC の subject で信頼──▶  UAMI(id-aks-pg-workload)  ──Entra 管理者──▶  PostgreSQL
        ▲                                                      ▲
        └ Pod が使う (annotation: client-id)                    └ AKS の OIDC issuer が発行したトークンを交換
```

## 前提

- `simple` のインフラが**デプロイ済み**（`learn/k8s/simple` で `just group-create` → `just deploy-local`）。
  - 既定のリソースグループ `rg-aks-demo` / デプロイ名 `main` の出力（ACR・AKS 名・PostgreSQL FQDN）を読む。
- `az login` 済み、`kubectl` あり（無ければ `simple` の `just install-kubectl`）。
- `az` の `postgres` 拡張が必要（`az extension add --name rdbms-connect` 等。初回は自動導入される場合もある）。
- **`simple`（および他の流用プロジェクト）のアプリ層は止めておく**ことを推奨。同じ単一 NGINX / 外部 IP を
  共有し、host 無しで `/` と `/api` を持つ Ingress 同士が衝突するため。インフラは残したまま
  `learn/k8s/simple` で `just app-down`（`just destroy` はインフラごと消すので使わない）。

## 構成

```
workload-identity/
├─ api/                       # Entra トークンで PG にパスワードレス接続する Flask API
│  ├─ app.py                 # DefaultAzureCredential でトークン取得 → password に渡す
│  ├─ Dockerfile
│  └─ requirements.txt       # + azure-identity
├─ front/                     # /api を叩き db.connected を色分け表示 (ロール付替を観察)
│  ├─ index.html
│  └─ Dockerfile
├─ main.bicep                 # 新規 Bicep は「UAMI + Federated Identity Credential」だけ
├─ manifests/
│  ├─ namespace.yaml
│  ├─ serviceaccount.yaml    # azure.workload.identity/client-id 注釈 (置換)
│  ├─ api-deployment.yaml    # SA 指定 + use:"true" ラベル。env に PGPASSWORD は無い
│  ├─ front-deployment.yaml
│  ├─ services.yaml
│  └─ ingress.yaml
├─ scripts/                   # 既存リソースへの in-place 更新と実験を az で分離
│  ├─ lib.ps1               # simple のデプロイ出力 + UAMI 情報の取得
│  ├─ acr-build.ps1
│  ├─ infra-prep.ps1        # AKS に OIDC issuer + Workload Identity を有効化
│  ├─ deploy.ps1            # main.bicep (UAMI+FIC) を OIDC issuer URL 付きでデプロイ
│  ├─ pg-entra.ps1          # PostgreSQL に Entra 認証を有効化 (1 回)
│  ├─ role-on.ps1 / role-off.ps1   # 【因果実験】PG の Entra 管理者を付け外し
│  ├─ credentials.ps1
│  ├─ apply.ps1             # 4 つのプレースホルダを置換して適用
│  └─ destroy.ps1
└─ justfile
```

## デプロイ手順

```pwsh
# 0) イメージを simple の ACR にビルド (api / front 各 1 種)。
just acr-build

# 1) セットアップ一括: AKS の WI 有効化 → UAMI/FIC 作成 → PG の Entra 認証 →
#    UAMI を PG 管理者に → 認証情報取り込み → マニフェスト適用。
just setup

just status
just ingress-ip          # 外部 IP が出たらブラウザでアクセス
```

> 個別に実行する場合は `just infra-prep` → `just deploy` → `just pg-entra` → `just role-on` →
> `just credentials` → `just apply` の順。`infra-prep` は数分かかる。

ブラウザで `http://<IP>/` を開き「2 秒ごとに自動更新」にチェックを入れておくと、後の実験で
`db.connected` が **true ⇄ false** に切り替わるのをリアルタイムに観察できる。

## 動作確認と「因果を確かめる」実験

### キーレスである証拠を見る

```pwsh
just curl-api      # has_pgpassword_env: false / db.connected: true / login_user に UAMI 名
just show-env      # Pod 内 env: AZURE_CLIENT_ID 等は注入されるが PGPASSWORD は無い
```

学び: `app.py` は `DefaultAzureCredential` で**毎回トークンを発行**し、それを `password` に渡している。
Workload Identity の webhook が、`use:"true"` ラベルの付いた Pod に
`AZURE_CLIENT_ID` / `AZURE_FEDERATED_TOKEN_FILE` などを注入し、SA トークン → UAMI トークンの
交換を成立させている。だから**機密を一つも配らずに** DB に到達できる。

### 実験 A — ロールを外すと接続が落ちる（auth トピックの RBAC を k8s に接続）

```pwsh
just role-off      # UAMI を PG の Entra 管理者から外す
just curl-api      # ← db.connected: false。error に認証拒否が出る (トークンは取れているのに)
just role-on       # 付け直す
just curl-api      # ← db.connected: true に戻る
```

学び: トークンの取得（認証）は成立しても、**DB 側にログイン権限（認可）が無ければ拒否される**。
「クレーム／ロールで挙動が変わる」という auth トピックの感覚が、k8s + Managed Identity + DB の
組み合わせでもそのまま効く。反映には数十秒の遅延が出ることがある（自動更新で観察すると見やすい）。

### 実験 B（任意）— SA の紐付けを壊すと交換が成立しない

`manifests/serviceaccount.yaml` の `client-id` をでたらめな GUID にして `just apply` →
`just logs` を見ると、トークン交換の段階で失敗する（FIC の subject と SA の対応が崩れるため）。
元に戻すには正しい `client-id` で `just apply` し直す。

学び: 三者（SA ↔ UAMI ↔ PG）のどの紐付けが切れても繋がらない。実験 A は「PG 側の認可」、
実験 B は「SA↔UAMI の信頼」を壊しており、**失敗箇所が層ごとに違う**ことを切り分けられる。

## 後片付け

```pwsh
just destroy       # 名前空間 + UAMI + PG 管理者登録を削除 (simple のクラスタ/インフラは残す)
```

AKS の OIDC/Workload Identity 有効化と PG の Entra 認証有効化は無害なので戻さない
（パスワード認証も残してあるので `config-rollout` 等のパスワード接続は壊れない）。
`simple` のインフラまで消したい場合は `learn/k8s/simple` 側で `just destroy`。

## 設計上の割り切り

- 新規 Bicep は **UAMI + Federated Identity Credential** のみ。AKS の WI 有効化・PG の Entra 認証・
  管理者の付け外しは既存リソースへの in-place 更新／頻繁に変える実験なので **az スクリプト**に置いた。
- UAMI を PG の**管理者**にして簡略化している。本来は `pgaadauth_create_principal` で
  最小権限の非管理ロールを作るのが望ましいが、ここでは「キーレス接続」と「ロールで挙動が変わる」
  体験に集中するための割り切り。
- PostgreSQL のパスワード認証は**残したまま**（`config-rollout` 等と共存させるため）。
