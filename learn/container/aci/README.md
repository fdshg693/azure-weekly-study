# container / aci — Azure Container Instances（1 コンテナを最短で載せる）

container トピックの **Step 2**（ロードマップは [../PLAN.md](../PLAN.md)）。
Step 1 [registry](../registry/) で **ACR に上げたイメージ**を、registry が用意した
**消費者 UAMI（AcrPull 済み）**で **キーレス pull** し、**Public IP / FQDN** で到達する。
オーケストレータを自前で持たない、もっとも素朴な「Azure にコンテナを 1 個動かす」道具。

共通方針（[../../CLAUDE.md](../../CLAUDE.md)）どおり：
**一般概念 → 最小構成で実装 → 設定を出し入れして因果を確かめる**／**構築・実行はユーザー自身が行う**。

> 構成と各実験の図は [MERMAID.md](MERMAID.md) を参照。

## 一般概念（ベンダー非依存）

- **コンテナを「ただ動かす」最小実行基盤**＝レジストリから image を pull し、1 ホスト上で起動して
  ネットワークに出すだけのもの。スケジューリング・自己修復・ロードバランスは**持たない**。
  Kubernetes（[../k8s/](../k8s/)）が「クラスタで賢く運用」する手前の、素の実行。
- **restartPolicy**: コンテナが終了したとき再起動するかの方針。`Always`／`OnFailure`／`Never` は
  Kubernetes の Pod の restartPolicy と同じ語彙で、コンテナランタイム一般の概念。
- **サイドカー / コンテナ同居**: 複数コンテナを 1 単位（ここでは Container Group）にまとめると
  **localhost とライフサイクルを共有**する。Pod の素朴版。
- **使った分だけ課金（per-second）**: 動いている間だけ課金され、消すと止まる。常駐サービスとも
  「起動して終わるバッチ」とも違う**使い捨ての中間形**。

## ACI 固有のポイント

- **Container Group**＝ACI のデプロイ単位。1 個でも複数でも「グループ」。Public IP / FQDN・
  再起動ポリシー・課金はグループ単位。
- **キーレス pull**: `imageRegistryCredentials` に **パスワードではなく UAMI の resource id（`identity`）**
  を指定する。registry で付けた **AcrPull** がそのまま効く（admin user も SP シークレットも使わない）。
- **FQDN**: `<dnsNameLabel>.<region>.azurecontainer.io`。`dnsNameLabel` はリージョン内で一意。

## このプロジェクトで作るもの

- [main.bicep](main.bicep)：web を 1 コンテナで公開する Container Group（Public IP/FQDN・keyless pull）。
- [restart.bicep](restart.bicep)：restartPolicy 実験用の「わざと終了するコンテナ」（公開なし）。
- [sidecar.bicep](sidecar.bicep)：web + sidecar を**同居**させ localhost 共有を見るコンテナグループ。

**ACR / UAMI は新規に作らず registry のデプロイ出力を参照する**（`acrLoginServer` / `uamiResourceId`）。
動的な値なので bicepparam は使わず [scripts/deploy.ps1](scripts/deploy.ps1) が registry の出力を読んで注入する。

## 前提

- **先に Step 1（[registry](../registry/)）を `task up` 済み**であること（ACR・イメージ `web:v1`・消費者 UAMI が要る）。
- Azure CLI（`az`）でログイン済み・サブスクリプション選択済み。
- [Task](https://taskfile.dev)（`task`）。
- **ローカル Docker は不要**（pull はすべて ACI 側＝クラウドで起こる）。

## 手順

```pwsh
# RG 作成 → web をデプロイ（registry の ACR から keyless pull）
task up

# 出力（FQDN / IP / URL）を確認 → HTTP で到達確認
task outputs
task probe        # build version 入りのページが返れば pull→配信 成功
```

## 因果を確かめる実験（ここが本体）

### 1. restartPolicy で再起動の有無が変わる

```pwsh
task restart-demo POLICY=OnFailure EXIT=1   # 異常終了 → 再起動して restartCount が増える
task restart-demo POLICY=OnFailure EXIT=0   # 正常終了 → 再起動しない（1 回で Terminated）
task restart-demo POLICY=Always    EXIT=0   # 正常終了でも毎回再起動する
task restart-demo POLICY=Never     EXIT=1   # 失敗しても再起動しない
task delete CG=cg-aci-restart               # 確認後は破棄（課金停止）
```

`Always`＝常に／`OnFailure`＝異常終了時のみ／`Never`＝しない。`restartCount` と `currentState` の差で体感する。
（k8s の Pod restartPolicy と同じ語彙が、オーケストレータ無しでも効くことを確認。）

### 2. キーレス pull（認可）— AcrPull を外すと pull が 403 で落ちる

Step 1 で「UAMI 本人は手元から使えないので SP で代役」した宿題を、ここで **UAMI 本人**で回収する。
ACI に assign した消費者 UAMI が ACR から pull できるのは **AcrPull があるから**。外すと pull が失敗する。

```pwsh
task acrpull-off      # 消費者 UAMI の AcrPull を剥奪（反映に数十秒）
task recreate         # ACI を作り直す（pull は起動時に走る＝作り直して再 pull させる）
task show             # events に "Failed to pull image" / 401|403 が出る

task acrpull-on       # AcrPull を付与し直す
task recreate         # 再 pull
task probe            # 今度はページが返る＝復活
```

> **なぜ recreate が要るか**: ACI はイメージを**コンテナ起動時に pull** する。実行中の Container Group を
> 再デプロイしても再 pull されないので、削除→作成で再 pull を起こす（[scripts/recreate.ps1](scripts/recreate.ps1)）。

認証（誰か＝UAMI）はそのまま・**認可（AcrPull の有無）だけ**で pull の可否が変わる＝認証と認可は別。
（触っているのは registry の Bicep が定義した割り当てそのもの。registry を再 deploy すれば元に戻る。）

### 3. コンテナグループ（同居 / サイドカーの最小形）

```pwsh
task sidecar                                      # web + sidecar を 1 グループに同居
task logs CG=cg-aci-sidecar CONTAINER=sidecar     # "[sidecar] reached web on localhost:80"
task delete CG=cg-aci-sidecar                      # 破棄
```

sidecar は公開ポートを持たず `http://localhost:80` で隣の web に届く＝**同居コンテナは network namespace を共有**する。
k8s の Pod 内マルチコンテナの素朴版。

### 4. per-second 課金（使い捨ての中間形）

```pwsh
task delete       # web の Container Group を消す＝その瞬間に課金が止まる
```

ACI は動いている間だけ per-second 課金。消せば止まる。VM の `deallocate`（[../../vm/](../../vm/)）や
automate の Job（起動→終了）と対比して、「常駐でも終わるバッチでもない、最短で 1 個動かす中間形」と位置づける。

## 後片付け（コスト注意）

```pwsh
task delete       # コンテナグループ単体を削除（課金停止）
task destroy      # この RG ごと削除（registry の RG は消さない）
```

> **次ステップへ**: ここで得た「素の 1 コンテナ」を基準に、Step 3 [webapp-container](../) は
> TLS／カスタムドメイン／デプロイスロットが最初から付く Web 専用ホストを、Step 4 container-apps は
> リビジョン分割／scale-to-zero を**マネージドが面倒見る**サービングを足していく。

## タスク一覧

| task | 説明 |
|---|---|
| `up` | group-create → deploy を一括 |
| `deploy [POLICY=Always]` | web の Container Group をデプロイ（keyless pull） |
| `outputs` / `probe` | 出力表示 / FQDN に HTTP 到達確認 |
| `show [CG=...]` | 状態・restartCount・pull/起動イベント |
| `logs [CG=... CONTAINER=...]` | コンテナのログ |
| `restart-demo POLICY=.. EXIT=..` | restartPolicy の差を観察 |
| `sidecar` | web + sidecar 同居（localhost 共有） |
| `acrpull-off` / `acrpull-on` | 消費者 UAMI の AcrPull 出し入れ |
| `recreate [POLICY=..]` | web を作り直して再 pull |
| `delete [CG=..]` / `destroy` | コンテナ単体削除（課金停止） / RG ごと削除 |
