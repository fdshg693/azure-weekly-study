# 学習トピック一覧（ユーザーの Azure レベル把握用）

このリポジトリは Azure を**トピックごとにサブフォルダで分け、各プロジェクトでコードを通して**
段階的に学ぶ構成。各トピックの詳細・概念の習得状況は `learn/{topic}/CLAUDE.md` に書く
（ここはトピック横断の短い概要に留める）。
共通方針は「**まず一般概念／最小構成 → 実装 → 設定を出し入れして因果を確かめる**」「**構築・実行は
ユーザー自身が行い、AI は Azure 上で実行しない**」。

> 注記: 各トピックの概要は代表プロジェクトを中心に**抜粋**している。全プロジェクトの網羅は
> 各 `learn/{topic}/CLAUDE.md` を参照。

## auth — 認証・認可（最も深く進んでいる領域）

`./auth`（詳細: [auth/CLAUDE.md](./auth/CLAUDE.md)、計画: [auth/PLAN.md](./auth/PLAN.md)）
技術: Bicep / just(Taskfile) / Azure CLI、必要に応じてフロント（バニラ JS + MSAL.js）。

OAuth 2.0 / OpenID Connect を土台に Entra ID を学ぶ。`entra-spa-login`（SPA で認証の最小ループ・
ID/アクセストークンの違い・PKCE）→ `api-protect`（自前リソースサーバー・JWT 検証・401/403）→
`app-roles-rbac`（App ロール・`scp` と `roles` の違い・クレームベース認可）→ `confidential-web`
（コンフィデンシャルクライアント・client_secret・BFF）→ `client-credentials-daemon`(**ユーザー不在**の
Client Credentials Flow・**委任許可 vs アプリケーション許可**・`.default`・管理者同意・`idtyp=app`）→
`on-behalf-of`（**多段 API**：SPA→中間 API(A)→下流 API(B)。**`aud` 境界**・**On-Behalf-Of トークン交換**
（`jwt-bearer`/`on_behalf_of`）・**アイデンティティ伝播**・委任同意 `oauth2PermissionGrant` の出し入れ）と、
**認証→認可、パブリック→コンフィデンシャル、ユーザー有→ユーザー不在、単段→多段**へ段階的に深化済み。

## func — Azure Functions

`./func`（詳細: [func/CLAUDE.md](./func/CLAUDE.md)）
技術: Terraform / Python v2 / Functions Core Tools。

`blob_logger`（Blob トリガー × 出力バインディングだけで入出力／ポーリング遅延／無限ループ回避）と
`func_keyvault`（Managed Identity × Key Vault × RBAC スコープを App 単位で分離、Reader/Writer、
auth level）。サーバーレスのトリガー／バインディングと、Functions から他リソースへの安全なアクセスを学習。
Event Grid トリガー化・キーレス化は未着手。

## storage — Azure Storage

`./storage`（詳細: [storage/CLAUDE.md](./storage/CLAUDE.md)）
技術: Terraform / just / Azure CLI。

`simple`（静的 Web サイトで `$web` だけ公開、公開フラグと SAS で「他は公開されない」を担保）と
`private_endpoint`（VNet + Private Endpoint + Private DNS Zone で閉域化、VM から内部到達／外部拒否を対比）。
**公開経路上の範囲制御**と**ネットワーク的閉域化**の 2 つの守り方を学習。

## network — ネットワーク

`./network`（詳細: [network/CLAUDE.md](./network/CLAUDE.md)）
技術: Bicep / just / Azure CLI。

`basic`（Azure での基本的なネットワーク構築＋通信一般）、`advanced`（より高度な内容）、
`memo`（ローカルでコマンドを叩く学習メモ、Git 管理外・指示なしでは触らない）。

## foundry — Azure AI Foundry（Agent Service）

`./foundry`（詳細: [foundry/CLAUDE.md](./foundry/CLAUDE.md)）
技術: Python（mgmt SDK / `azure-ai-projects` / Agent Framework）/ just。

`prompt_agent`（エージェント定義を Foundry 側に作り、リソース作成〜会話までほぼ Python で一周）、
`ephemeral_agent`（定義をコード内に持つエフェメラル、ツールの実行場所＝サーバー vs ローカルの違い）、
`hosted_agent`（ホステッドの入口、サンプル取得のみで自作デプロイは未着手）。
コントロール／データプレーンの 2 層、Foundry のロールとモデルデプロイ課金感覚を学習。

## k8s — AKS（Azure Kubernetes Service）

`./k8s`（詳細: [k8s/CLAUDE.md](./k8s/CLAUDE.md)、計画: [k8s/PLAN.md](./k8s/PLAN.md)）
技術: Bicep / just / Azure CLI / kubectl、サンプルは Flask API + nginx 静的フロント。

`simple`（ACR/AKS/AcrPull/PostgreSQL を Bicep で束ね、Deployment・ClusterIP Service・単一 Ingress・
HPA・Secret の `envFrom`・probe・自己修復まで一周）→ `config-rollout`（simple のインフラを流用し、
**ConfigMap（非機密）vs Secret（機密）** の使い分け、**RollingUpdate（maxSurge/maxUnavailable）** と
`rollout undo`、壊れた readiness probe でロールアウトが止まる挙動、namespace 隔離を体感）→
`workload-identity`（**Workload Identity** で DB 接続を**キーレス化**。UAMI + Federated Identity Credential と
ServiceAccount の紐付け、PostgreSQL の Entra 認証でパスワードレス接続。ロール付け外しで接続が変わり
**認証と認可の分離**を体感）→ `helm-kustomize`（**マニフェストのテンプレート化と環境差分**。同じベースを
**Kustomize の overlay** と **Helm の values** の両方で dev/prod に出し分け、`__ACR__` の sed を images transformer /
`--set` に置換。レンダリング差分で「同じベース→差分だけで 2 環境」を可視化し、2 ツールを比較）→
`observability`（**可観測性**。既存クラスタに監視を後付けし、Container Insights（Log Analytics）→ マネージド
Prometheus + Managed Grafana の 2 段階で有効化。`/work` で負荷を掛けて HPA のスケールアウトを起こし、
**同じ時間軸の CPU グラフから「HPA がなぜスケールしたか」を裏側で理解**。`crash`/`self-heal` で再起動も観察）。
最小構成 → 設定とロールアウト → キーレス化 → テンプレート化 → 可観測性、へ段階的に深化中。永続化・TLS は未着手。

## vm — 仮想マシン（IaaS）

`./vm`（詳細: [vm/CLAUDE.md](./vm/CLAUDE.md)、計画: [vm/PLAN.md](./vm/PLAN.md)）
技術: Bicep / just / Azure CLI。

`simple`（VNet/Subnet/NSG/Public IP/NIC/Linux VM を最小構成で作り、**SSH 鍵認証（パスワードレス）**で
ログイン。NSG の 22/80 を出し入れして到達を切り替え、**「プロセスが動く」と「NSG で届く」は別**を体感。
**`stop` vs `deallocate`** の課金差、**Dynamic な Public IP が再起動で変わる**様子を確認）。
network トピックの「到達確認の道具」から脱し、VM 本体を主役にマネージドとの責任分界を学び始めた段階。
cloud-init・Managed Identity・自前 DB は未着手。

## db — マネージドデータベース（PaaS）

`./db`（詳細: [db/CLAUDE.md](./db/CLAUDE.md)、計画: [db/PLAN.md](./db/PLAN.md)）
技術: Bicep / just / Azure CLI / Python（`psycopg`）。

`simple`（**PostgreSQL Flexible Server**（Burstable B1ms / v16 / パスワード認証 / パブリックエンドポイント）と
論理 DB を Bicep で作り、ローカルの Python から**テーブル作成→INSERT→SELECT**を一周。`.env` に接続情報、
`init-env` が PGPASSWORD 生成、`deploy` が PGHOST 書き戻し。**ファイアウォール規則は Bicep に書かず** just で
出し入れし、作成直後は許可 0 件で繋がらない→自分の IP を足す／外すで接続が通る⇄拒否される、で
**「マネージド DB はデフォルトで閉じている／経路はあるが許可制」**を体感（vm の NSG と同型）。TLS 必須・
マネージド DB の課金感覚（VM の deallocate に当たる気軽な停止が無い）も学習）。
vm（自前 DB＝IaaS）と対比した PaaS の入口。Entra 認証パスワードレス・Private Endpoint・PITR/スケール・Cosmos は未着手。

## automate — 自動化／バッチ実行

`./automate`（詳細: [automate/CLAUDE.md](./automate/CLAUDE.md)）
技術: Bicep / just / Azure CLI（`az containerapp` / `az automation`）/ ACR Tasks。

「**常駐させない実行モデル**」が軸。`simple`（**Azure Container Apps Jobs** の Schedule トリガーで
「起動 → 仕事 → 終了」を cron 定期実行 ＋ 手動起動。Bicep で Log Analytics/Environment/ACR/UAMI(AcrPull)/Job を
作り、ワーカーは終了コードで成否を表す。**App と Job の違い**、**execution と replica**、`parallelism`/
`replicaRetryLimit` の出し入れ、MI+AcrPull のキーレス pull を体感）→ `runbook`（**Azure Automation** の
PowerShell runbook で VM を Start/Stop。イメージを持たず Azure 提供ランタイムで走らせ、アカウントの
**system-assigned MI で Azure を操作**。**Reader/VM Contributor の付け外し**で認証と認可の分離、
**Automation 変数**で設定とコードの分離、**タイムゾーン付きスケジュール**を体感。`vm/simple` の deallocate を
runbook に自動化させる位置づけ）。Event(KEDA) 駆動・Webhook は未着手。
