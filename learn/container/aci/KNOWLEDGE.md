# KNOWLEDGE — container/aci で新たに出た用語・概念

ACR / Managed Identity / AcrPull / RBAC / `az acr build` は **registry（Step 1）で既出**なので再掲しない。
ここでは ACI を主役にして初めて要る語に絞る。

## Azure Container Instances (ACI) の構造

- **Container Group（コンテナグループ）**: ACI のデプロイ単位。**1 個以上のコンテナを 1 ホストに同居**させ、
  **ネットワーク（localhost）・IP・ライフサイクル・課金をグループ単位で共有**する。1 コンテナでもグループ。
  Kubernetes の **Pod に相当する素朴版**（スケジューラ・自己修復・複数ノードは無い）。
- **OS type / SKU**: `osType: Linux`、`sku: Standard`（汎用）。
- **resources.requests（cpu / memoryInGB）**: コンテナへの割り当て。割り当て量 × 起動時間で課金される。
- **ipAddress.type = Public + dnsNameLabel**: グループに **Public IP** と
  **FQDN `<dnsNameLabel>.<region>.azurecontainer.io`** を付与（`dnsNameLabel` はリージョン内一意）。
  `ipAddress` を持たない＝外部公開なし（restart 実験の crasher はこれ）。

## restartPolicy（再起動ポリシー）

コンテナが**終了したとき**どうするか。Kubernetes の Pod と同じ語彙：

- **Always**: 終了コードに関わらず**毎回再起動**（常駐サービス向けの既定）。
- **OnFailure**: **異常終了（exit != 0）のときだけ**再起動。正常終了なら止まる（バッチ向け）。
- **Never**: 何があっても再起動しない（1 回実行して終わり）。
- 観察点: `containers[0].instanceView.restartCount`（再起動回数）と
  `currentState.state`（Running / Terminated / Waiting）と `exitCode`。

## キーレス pull（ACI から ACR へ）

- **`imageRegistryCredentials[].identity`**: レジストリ資格情報に **パスワードではなく UAMI の resource id** を
  指定すると、その **Managed Identity で ACR にアクセス**して pull する＝**共有秘密ゼロ（キーレス）**。
  registry で付けた **AcrPull** がそのまま効く（admin user も SP シークレットも使わない）。
- **`identity.userAssignedIdentities`**: Container Group に UAMI を assign。`imageRegistryCredentials.identity`
  はここで assign した UAMI を指す。
- **pull のタイミング = コンテナ起動時**。だから AcrPull を剥奪した効果を見るには
  **作り直して再 pull させる**必要がある（実行中の再デプロイでは再 pull されない）。
- AcrPull が無いと pull は **401/403** で失敗し、`instanceView.events` に "Failed to pull image" が出る。
  認証（UAMI という誰か）はそのまま・**認可（AcrPull）だけ**で可否が変わる＝registry の authn/authz 分離を実 pull で回収。

## サイドカー / 同居コンテナ

- 同じ Container Group のコンテナは **localhost を共有**（network namespace 共有）。
  公開ポートを持たない sidecar から `http://localhost:80` で隣のコンテナに届く。
- これが **Pod 内マルチコンテナ（sidecar パターン）の最小形**。ログ収集・プロキシ・認証代理などに使う。

## 課金モデル（per-second）

- ACI は **動いている間だけ per-second 課金**（cpu/メモリ割り当て × 秒）。**Container Group を消すと即停止**。
- 対比:
  - **常駐サービス**（App Service / Container Apps App）= 動かし続ける前提。
  - **終わるバッチ**（automate の Container Apps Jobs）= 起動→仕事→終了。
  - **VM**（[../../vm/](../../vm/)）= `deallocate` で課金を止める（停止だけでは止まらない）。
  - ACI はその中間＝**最短で 1 個動かして、要らなくなったら消す使い捨て**。

## よく使う CLI

- **`az container show`**: 状態・`restartCount`・`currentState`・`events`・`environmentVariables` を確認。
- **`az container logs --name <cg> [--container-name <c>]`**: コンテナの標準出力。複数同居時は `--container-name`。
- **`az container delete`**: Container Group を削除＝課金停止。
- ※ デプロイは `az deployment group create`（Bicep）。ACI は `az container create` でも作れるが、
  本プロジェクトは他トピックと揃えて Bicep を主経路にしている。
