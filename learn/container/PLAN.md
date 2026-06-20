# コンテナ（Azure マネージドコンテナ）学習プラン — 何から作るか

このファイルは container トピックの**プロジェクト設計の目安（ロードマップの正本）**。
このトピックはまだプロジェクトが無いので、ここでは「最初の最小構成 → どう深化させるか」を定める。
方針はリポジトリ共通（[../CLAUDE.md](../CLAUDE.md)）どおり:
「**一般概念／最小構成 → 実装 → 設定を出し入れして因果を確かめる**」「**構築・実行はユーザー自身が行い、AI は Azure 上で実行しない**」。

---

## 0. 責務分け（重複回避） — このトピックの担当範囲はどこまでか

コンテナ関連は既存トピックと重なりやすいので、**何を扱い／何を扱わないか**を最初に明示する。
このトピックの軸は **「自作コンテナイメージを、オーケストレーションを自前で持たずに Azure のマネージド計算へ
そのまま載せて動かす」**。＝ ローカルで作ったイメージ（[../../local/docker/](../../local/docker/)）と、
フルオーケストレーション（[../k8s/](../k8s/)）の **あいだ** を埋めるのが担当。

| トピック | 担当範囲（やること） | このトピックとの境界（やらないこと） |
|---|---|---|
| [../../local/docker/](../../local/docker/)（ローカル / Azure 不要） | コンテナ**単体**の中身。イメージの作り込み（マルチステージ・レイヤ・BuildKit）、ランタイム挙動（PID1・cgroups・namespace）、ローカルの network/volume、Compose。「良いイメージを作る・1 台を理解する」まで。 | **Azure には出さない**。クラウドのホスティング・課金・MI 認証は扱わない。 |
| **container（このトピック）** | 作ったイメージを **Azure マネージドにそのまま載せる**。ACR（クラウドの置き場＋ビルド）、ACI（最小の単一コンテナ）、Web App for Containers（App Service の PaaS Web）、**Container Apps の App（常駐サービング）側**。「どのサービスをいつ使うか」の地図を作る。 | **k8s クラスタを自分で持つ範囲は扱わない**（→ k8s）。**起動して終了する非常駐バッチ（Job 側）は扱わない**（→ automate）。 |
| [../k8s/](../k8s/)（AKS） | **フルオーケストレーション**。複数コンテナのスケジューリング、Service/Ingress、HPA、Deployment/rollout、Workload Identity、Helm/Kustomize、可観測性。「クラスタを自分で運用してでも欲しい制御」を得る段。 | マネージドに丸投げで済む単純なホスティングはここでは主役にしない（→ このトピック）。 |
| [../automate/](../automate/)（自動化） | **常駐させない実行**。**Container Apps の Job 側**（起動→仕事→終了）と Automation runbook。 | **Container Apps の App（常駐・サービング）側は扱わない**（→ このトピック）。 |

> **最重要の境界 2 つ**
> 1. **Container Apps は automate と分担**: automate は **Job（バッチ・終了コードで評価）**、このトピックは
>    **App（常駐サービス・Ingress とリビジョンで評価）**。同じ Container Apps を「終わる仕事」と「動き続けるサービス」で割る。
> 2. **ACR の扱い**: k8s / automate は ACR を **手段（AcrPull で pull するだけ）**として使ってきた。
>    このトピックでは ACR を **主役（リポジトリ・tag/digest・ACR Tasks・スキャン）**として正面から扱う。

---

## 1. このトピックで学びたいこと（ゴール像）

「コンテナを Azure で動かす」には複数の選択肢があり、**マネージドに任せる範囲（自由度↔手間）が段階的に違う**。
その**スペクトラム（ACI → Web App for Containers → Container Apps → AKS）**を体で覚え、
「**この要件ならどれ**」を自分で選べるようになるのがゴール。

- **クラウドのイメージ置き場**: ACR（リポジトリ／tag vs digest／`az acr build` によるクラウドビルド／脆弱性スキャン）。
- **最小の実行**: ACI で単一コンテナを Public IP/FQDN 付きで起動。restartPolicy・per-second 課金・コンテナグループ。
- **PaaS Web ホスティング**: Web App for Containers（App Service）。マネージド TLS／カスタムドメイン／デプロイスロット／ヘルスチェック。
- **サーバーレスコンテナ（サービング）**: Container Apps の App。Ingress・**リビジョンとトラフィック分割**・**scale-to-zero / HTTP スケール**。
- **キーレス pull**: どのサービスでも **Managed Identity + AcrPull**（auth / k8s / automate の RBAC を踏襲）で接続文字列レス。
- **選択の地図**: 4 サービスを「常駐性・スケール・ネットワーク・運用負荷・課金」の軸で並べ、使い分けを言語化。

## 2. 推奨ロードマップ（やさしい順）

各プロジェクトは `learn/container/{name}/` に置く想定。「**1 プロジェクト = 主役の概念 1〜2 個**」に絞る。
**ローカルで作ったイメージ（local/docker）を ACR に上げ、各サービスが同じ ACR から引く**形で全ステップを貫く。

### Step 1 — `registry`（ACR が主役・後続の土台）
**主役**: クラウドのイメージ置き場としての Azure Container Registry。
- ローカルの docker イメージを `az acr login` → push、さらに **`az acr build`（ACR Tasks）**でクラウド側ビルド（ローカル Docker 不要）。
- **因果を確かめる実験**: admin user の 有効／無効、**AcrPull ロール**を付けたサービスからの **キーレス pull** ⇄ 権限を外すと pull 失敗。
  `local/docker` 案7 でやった **tag vs digest（内容ハッシュ＝不変）** をクラウドの ACR で再確認（同タグ上書きで digest が変わる）。
- `az acr repository list/show-tags`、`az acr task`、イメージスキャン（Defender / `az acr` のスキャン）。
- これ以降の全ステップは「ここに上げたイメージを各サービスが引く」前提なので、最初に固める。

### Step 2 — `aci`（Azure Container Instances が主役）
**主役**: もっとも素朴な「1 コンテナを Azure に載せる」。オーケストレータ無し。
- ACR のイメージを **ACI** で起動し、**Public IP / FQDN** で到達。env・cpu/memory 割り当て・**MI(AcrPull) でキーレス pull**。
- **因果を確かめる実験**: **restartPolicy（Always / OnFailure / Never）**を切り替え、コンテナが異常終了したときの再起動挙動の差を観察。
  **コンテナを削除すると課金が止まる（per-second 課金）**＝「使い捨ての中間形」を体感（vm の deallocate、automate の Job と対比）。
- **コンテナグループ**（複数コンテナ同居）に触れ、sidecar の最小形を知る。
- **位置づけ**: 「常駐サービス」でも「終わるバッチ」でもない、最短で 1 個動かす道具。ここを基準点に上位サービスの“足し算”を測る。

### Step 3 — `webapp-container`（Web App for Containers が主役）
**主役**: App Service にカスタムコンテナを載せる PaaS Web ホスティング。
- ACR のイメージを **Web App for Containers** にデプロイ。`WEBSITES_PORT`、App Settings 注入、ヘルスチェック。
- **マネージド TLS（`https://...azurewebsites.net`）／カスタムドメイン／デプロイスロット**という Web 向けの足回りを得る。
- **因果を確かめる実験**: **デプロイスロット**に新リビジョンを置き、**swap で無停止入れ替え**→ 問題があれば swap で戻す。
  App Settings を変えて再起動で反映、プランのスケールアウト（インスタンス数）で並列が増えるのを確認。
- **ACI との対比**: ACI は素の 1 コンテナ。App Service は **TLS／ドメイン／スロット／Always On** が最初から付く Web 専用ホスト。
  「何を足してくれるか」で 2 サービスの守備範囲の違いを言語化。

### Step 4 — `container-apps`（Container Apps の App 側が主役）
**主役**: サーバーレスコンテナのサービング。**automate の Job 側と対になる「App 側」**。
- ACR のイメージを **Container Apps の App**（Ingress 有効）としてデプロイ。Environment・シークレット・MI(AcrPull)。
- **リビジョンとトラフィック分割**: 新旧 2 リビジョンへ **50/50 → canary → 100%** とトラフィックを振り、無停止で切り替え。
- **scale-to-zero / HTTP スケール**: `minReplicas=0` で**アクセスが無いと 0 レプリカ**（コールドスタート）、HTTP 同時実行ルールで負荷に応じて増える。
- **因果を確かめる実験**: トラフィック配分を変えて応答（バージョン）の比率が変わる／`minReplicas` を 0⇄1 にしてコールドスタートの有無を観察／
  同時実行スケールルールを締める・緩めるでレプリカ数が変わる。
- **automate（Job）との対比**: 同じ Container Apps でも **App＝常駐・Ingress とリビジョンで評価**、**Job＝起動して終了・終了コードで評価**。
  「**サービスとして動き続ける**」か「**仕事をして終わる**」かが分かれ目だと回収する。
- **k8s への橋渡し**: Ingress／スケール／リビジョンを**マネージドが面倒見る**のが Container Apps。
  これらを**自分で全部制御したく**なったら AKS（[../k8s/](../k8s/)）へ、という上り口を示す。

### Step 5（発展）— `choose` / Dapr / VNet 統合
**主役**: 4 サービスの**選択の地図**と、Container Apps の発展機能。
- **選択の地図**: ACI / Web App for Containers / Container Apps / AKS を「**常駐性・スケール（scale-to-zero/HPA）・
  ネットワーク（公開/内部/VNet）・運用負荷・課金モデル**」の軸で 1 枚に整理し、要件→サービスを引けるようにする。
- **Container Apps の発展**: **Dapr**（サービス間呼び出し・state/pub-sub のサイドカー）、**複数コンテナ（sidecar）**、
  **VNet 統合・内部限定 Ingress**（storage/network トピックの閉域化と接続）。

## 3. 進め方のメモ

- 各プロジェクトに共通構成（`README.md` / `KNOWLEDGE.md` / `justfile` または `Taskfile.yml`）を置く。複雑になったら Taskfile。
- **イメージは local/docker の成果物を流用**してよい（このトピックの主眼は「作る」ではなく「載せる」）。
  ただしサンプルが必要なら最小の Web サーバー（既存の Flask API / nginx）を `az acr build` で焼く。
- **キーレス化を一貫させる**: どのサービスでも ACR からの pull は **MI + AcrPull** を第一選択にし、admin user は対比用に留める
  （auth / k8s / automate と同じ「認証と認可は別」を再確認）。
- **コスト注意**: ACI は per-second、Container Apps は scale-to-zero で止まるが、App Service プランや Container Apps
  Environment は**持っているだけで課金**になりうる。各 README に「使い終わったら破棄／stop」を明記する。
- **ドキュメント更新**: 最初のプロジェクトを 1 つ追加したタイミングで `learn/container/CLAUDE.md`（習熟度）を作成し、
  [../CLAUDE.md](../CLAUDE.md)（トピック横断の概要）にも container トピックの行を追記する。
