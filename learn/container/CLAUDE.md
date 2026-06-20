# container（マネージドコンテナ）トピック — ユーザーのレベル感と次プロジェクトの目安

このトピックは **「自作コンテナイメージを、オーケストレーションを自前で持たずに Azure の
マネージド計算へそのまま載せて動かす」** を軸に、`learn/container/{name}/` の各プロジェクトで
段階的に学ぶ。ロードマップの正本は [PLAN.md](./PLAN.md)、責務分け（local/docker・k8s・automate との
境界）もそこに定義済み。共通方針はリポジトリ全体と同じ「**一般概念／最小構成 → 実装 →
設定を出し入れして因果を確かめる**」「**構築・実行はユーザー自身、AI は Azure 上で実行しない**」。

スペクトラム **ACI → Web App for Containers → Container Apps → AKS** を体で覚え、
「この要件ならどれ」を選べるようになるのがゴール。

## 使用技術

- 環境構築は **Bicep**。
- コマンド集約は **Taskfile**（`task`）＋ `scripts/*.ps1`（PowerShell の実体を .ps1 に切り出す）。
  justfile ではなく Taskfile を採用（ユーザー指定。auth トピックの後半と同じ方針）。
- イメージは **ACR Tasks（`az acr build`）** でクラウド側ビルド（ローカル Docker 不要）。
- ACR からの pull は **Managed Identity + AcrPull**（auth/k8s/automate の RBAC を踏襲・キーレス第一）。

## プロジェクト一覧

### `registry` — Azure Container Registry が主役（Step 1・後続の土台）
`./registry`

container トピックの最初のプロジェクト（[PLAN.md](./PLAN.md) Step 1）。後続の全ステップが
「ここに上げたイメージを pull する」前提なので、まず **ACR** を土台として固める。
Bicep で **ACR（admin user 既定無効＝キーレス）＋ 消費者 UAMI ＋ AcrPull** を作り、最小の nginx
イメージ（[app/](./registry/app/)、build-arg `VERSION` をページに焼き込む）を `az acr build` でクラウドビルド。
**因果を確かめる実験**: `digest-demo` で**同じタグ `v1` を中身だけ変えて再ビルド → digest が変わる**
（tag は動く参照・digest は不変の指し先）／`admin-on`・`admin-off` で **admin user（共有パスワード）と
Entra トークン認証（`az acr login`）＝キーレス**の対比／`acrpull-*`（setup→pull→revoke→pull→grant→cleanup）で
**AcrPull だけ持つ SP を非特権 ID の代役にして pull の成功⇄403 をローカル段階観測**（UAMI はマネージド ID ゆえ
手元から使えない＝IMDS 経由のため SP で代替。`pull` はロールを触らないので反映待ちでも再実行で観測可。
`docker login`(認証)は通るが pull(認可)が落ちる＝認証と認可の分離も同時に体感）。消費者 UAMI 本人を主語にした
実 pull 403 体感は計算リソースが要るため Step 2 の aci へ送り、Step 1 は AcrPull を付けた土台（Bicep）まで。
肝は **repository / tag / digest の構造**、**認証(admin user vs Entra トークン)と認可(AcrPull/AcrPush)の分離**、
**ACR Tasks（ビルド場所＝レジストリ側）**。

### `aci` — Azure Container Instances が主役（Step 2）
`./aci`

container トピックの 2 番目（[PLAN.md](./PLAN.md) Step 2）。「**オーケストレータ無しで 1 コンテナを最短で Azure に載せる**」。
registry の **ACR / イメージ `web:v1` / 消費者 UAMI をそのまま参照**し（新規に作らない・`deploy.ps1` が registry の
デプロイ出力を読んで注入）、**`imageRegistryCredentials.identity` に UAMI を指定して keyless pull**、**Public IP / FQDN**
で到達する（registry で「UAMI 本人の pull は計算リソースが要る」と送った宿題をここで回収）。
**因果を確かめる実験**: `restart-demo` で **restartPolicy（Always/OnFailure/Never）× exitCode** の組合せから再起動の有無
（`restartCount`）を観察／`acrpull-off → recreate → show` で **消費者 UAMI 本人の AcrPull を剥奪すると pull が 403**
（pull は**起動時**なので作り直して再 pull させる＝認証はそのまま・認可だけで可否が変わる）／`sidecar` で
**コンテナグループ同居＝localhost 共有**（Pod 内マルチコンテナの最小形）／`delete` で **per-second 課金が消すと止まる**
（vm の deallocate・automate の Job と対比した「使い捨ての中間形」）。Container Group＝Pod の素朴版という位置づけ。

## 学習済みの概念

- **レジストリの構造**: repository / tag（可動ラベル）/ manifest / **digest（内容ハッシュ＝不変）**。
  同じタグの上書きで digest が変わる／古い digest は dangling として残り digest 指定で pull 可。
- **ACR の認証**: admin user（共有パスワードのアンチパターン）vs **`az acr login` の Entra トークン認証**（キーレス）。
- **ACR の認可ロール群**: AcrPull / AcrPush / AcrDelete を ACR スコープで割り当て（automate/k8s は AcrPull のみだった）。
- **ACR Tasks（`az acr build`）** を「ビルド場所＝レジストリ側」という主役として再確認、`--build-arg`。
- `az acr manifest list-metadata` / `repository show-tags` / `check-health`。

### ACI（Step 2 で学習済み）
- **Container Group**＝ACI のデプロイ単位（**Pod の素朴版**）。1 ホストに同居・**localhost/ライフサイクル/課金をグループ共有**。
- **Public IP + `dnsNameLabel`** で **FQDN `<label>.<region>.azurecontainer.io`** 到達。`ipAddress` 無し＝非公開。
- **restartPolicy**（Always/OnFailure/Never）と `restartCount` / `currentState` / `exitCode` の観察。
- **keyless pull**: `imageRegistryCredentials.identity` に UAMI を指定（パスワードレス）。**pull は起動時**＝
  AcrPull 剥奪の効果は作り直して再 pull させて観測（**UAMI 本人の 403** で authn/authz 分離を回収）。
- **サイドカー / 同居**＝localhost 共有（Pod 内マルチコンテナの最小形）。
- **per-second 課金**＝消すと止まる「使い捨ての中間形」（vm の deallocate / automate の Job と対比）。
- `az container show` / `logs` / `delete`。

## まだ触れていない主要概念（次プロジェクトの候補 = PLAN の Step 3〜5）

- **Web App for Containers**（Step 3）: App Service の PaaS Web、`WEBSITES_PORT`、マネージド TLS／
  カスタムドメイン／**デプロイスロットの swap**。
- **Container Apps の App 側**（Step 4）: Ingress・**リビジョンとトラフィック分割**・**scale-to-zero / HTTP スケール**
  （automate の Job 側と対）。
- **選択の地図 / 発展**（Step 5）: 4 サービスを常駐性・スケール・ネットワーク・運用負荷・課金で整理、Dapr・VNet 統合。
- **イメージスキャン**: Defender for Containers の有効化と結果確認（registry では設定言及のみ）。
