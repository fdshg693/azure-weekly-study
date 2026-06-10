# Step12: 観測とトラブルシュート — Network Watcher / NSG フローログ

このステップでは、Step1〜4 で **ping や `ssh -J` を使って「通った／通らない」を都度たしかめてきた疎通**を、**通信ログ・経路診断として体系的に観測する**構成を学びます。これは「候補H」として計画されていたものです。

これまでは「NSG を出し入れ → ping して結果を見る」という**体で確かめる**やり方でした。本ステップは同じ出し入れを、**「なぜ通った／通らないか（どのルールが効いたか・どの経路を通るか）」を後追いで説明できる**観測ツールに置き換えます。新しいリソースを足すというより、**既存ステップの検証を補強する横断ステップ**です。

## 学ぶ概念
- **IP Flow Verify（NSG 評価の可視化）**: 実際にパケットを流さずに、「送信元・宛先・ポート・プロトコル」を指定して **NSG が許可するか拒否するか、そして“どのルール”が効くか**を判定します。Step1/4 の「許可を出し入れして ping」を、結果（access と ruleName）として読める形にします。
- **接続トラブルシュート（connectivity test）**: 送信元 VM から実際に宛先へパケットを出し、**到達可否と経路（ホップ）・遅延**を返します。ping の「通った」を、経路つきで説明できる観測に変えます。
- **Next Hop（経路診断）**: ある宛先へのパケットが **次にどこへ向かうか**を UDR 込みで返します。Step3 の「経路を成立させているのは何か（ピアリングか UDR か）」を、判定結果として観測します。
- **NSG フローログ**: NSG を通過した**許可/拒否トラフィックを Storage に記録**します。都度の ping ではなく、**後から見返せる通信ログ**を残します。

## これまでのステップとの対比

| 観点 | Step1〜4（これまで） | Step12（本ステップ） |
| --- | --- | --- |
| 確かめ方 | ping / `ssh -J` を実行して結果を見る | 診断ツールで判定・記録を観測する |
| 「なぜ」 | 結果から推測する | **どのルール／どの経路か**が返ってくる |
| トラフィック | 実際に流す必要がある | IP Flow Verify は**流さずに**判定できる |
| 後追い | その場限り（残らない） | フローログとして**記録が残る** |

## 構成
- **VNet**: `vnet-observe` (`10.0.0.0/16`)
  - `subnet-app` (`10.0.1.0/24`): NSG `nsg-app` を関連付け
- **NSG**: `nsg-app` … `Allow-SSH-From-Vnet`（VNet 内からの TCP 22 だけ許可。それ以外の inbound は既定の `DenyAllInBound` で拒否）
- **VM**: `vm-a`（観測する側／接続トラブルシュートの送信元）・`vm-b`（観測される側／宛先）。どちらもパブリック IP なし・Ubuntu 22.04・**Network Watcher Agent 拡張**入り
- **Storage**: フローログの保存先（`stflow...`）

> **Note**: 環境は Step1/4 の最小再現です。主役はリソースではなく「観測のしかた」なので、構成は意図的に小さくしてあります。

## 手順

### 1. リソースのデプロイ

```bash
cd step12
just deploy
just info
```
> Network Watcher Agent 拡張の導入に数分かかります。

### 2. IP Flow Verify — 「通る／通らない」を理由つきで観測

```bash
just verify-allow   # VNet 内からの SSH → Allow（rule: Allow-SSH-From-Vnet）
just verify-deny    # Internet からの SSH → Deny（rule: DefaultRule_DenyAllInBound）
```
パケットを 1 つも流さずに、NSG の判定結果が返ってきます。`verify-allow` は**明示の許可ルール**で通り、`verify-deny` は**既定の拒否ルール**で落ちる——「許可は明示・拒否は既定」という Step1/4 の構図が、`access` と `ruleName` という形で読めます。

### 3. 接続トラブルシュート — ping を経路つきの観測に

```bash
just test-conn   # vm-a -> vm-b:22 が Reachable か、経路（ホップ）と遅延つきで返る
```
Step2 で Run Command の ping を見ていたものを、**到達可否＋経路**として観測できます。

### 4. Next Hop — 経路を診断する

```bash
just next-hop    # vm-b 宛て=VnetLocal / Internet 宛て=Internet
```
「この宛先のパケットは次にどこへ向かうか」が返ります。UDR を入れた構成（Step3）なら、ここに `VirtualAppliance`（NVA/Firewall）が現れ、**経路を曲げているのが UDR である**ことを判定として確認できます。

### 5. NSG フローログ — 通信ログを記録して見返す

```bash
just flow-log-on        # NSG フローログを Storage に有効化
just flow-log-status    # 有効状態・保存先を確認
just generate-traffic   # vm-a -> vm-b に何度かアクセスして記録対象を作る
just flow-log-blobs     # 記録された blob を一覧（反映まで数分）
```
都度の ping と違い、許可/拒否トラフィックが**後から見返せるログ**として Storage に残ります。

### 6. 出し入れして因果を観測する（Step1〜11 と同じ手法）

```bash
just verify-allow   # いまは Allow（rule: Allow-SSH-From-Vnet）
just lock           # SSH 許可より高優先度(90)の Deny ルールを追加
just verify-allow   # access が Deny / rule が Deny-SSH-From-Vnet に変わる
just unlock         # Deny ルールを削除
just verify-allow   # 再び Allow / rule が Allow-SSH-From-Vnet に戻る
```
これまでは「ルールを出し入れ → ping して通る/通らないを体感」でしたが、本ステップでは **通信を 1 つも流さずに、判定が Allow⇄Deny と切り替わり、“効いているルール名”まで変わる**ことを観測できます。因果（何が許可/拒否を決めているか）を、結果の推測ではなく**ツールの判定**として切り分けられるのが本ステップの本質です。

## クリーンアップ

```bash
just flow-log-off   # （任意）フローログを無効化
just destroy
```
