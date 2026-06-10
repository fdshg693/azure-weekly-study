# Step11: egress の中央集約と検査 — Azure Firewall

このステップでは、各スポークが勝手にインターネットへ出るのではなく、**ハブの 1 か所（Azure Firewall）を必ず経由させ、許可した宛先（FQDN）だけ外へ出す**構成を学びます。これは「候補D」として計画されていたものです。

Step3（ハブ&スポーク / 自前 NVA）で手組みした「中継 VM」を、**マネージドなファイアウォール**へ置き換える発展であり、Step5（NAT Gateway / egress の集約）に「検査・制御」を足したものとも言えます。

## 学ぶ概念
- **egress の中央集約（強制トンネリング）**: スポークの UDR で `0.0.0.0/0`（=あらゆる外向き）を Firewall に向け、出口をハブの 1 か所に矯正します。各スポークが個別に外へ出る経路を塞ぎ、すべての外向きを 1 か所で検査・制御できるようにします。
- **FQDN フィルタリング（アプリケーションルール）**: 「どの IP か」ではなく「どのドメイン（FQDN）か」で許可/拒否を判断します。HTTPS では SNI、HTTP では Host ヘッダを見て一致判定します。許可リストにない宛先はすべて拒否されます。
- **ステートフルなマネージド NVA**: Azure Firewall は、Step3 で手組みした NVA（OS の `ip_forward` で素通しするだけ）と違い、マネージドで冗長・スケールし、通信の中身を見て許可/拒否できます。
- **Firewall による SNAT**: 出口を通った外向き通信の送信元は、Firewall の公開 IP に集約されます（Step5 の NAT Gateway と同じ「出口の集約」ですが、Firewall は集約に加えて検査も行う点が違います）。

## これまでのステップとの対比

| 観点 | Step3: 自前 NVA | Step5: NAT Gateway | Step11: Azure Firewall |
| --- | --- | --- | --- |
| 役割 | spoke 間の中継（ルーティング） | egress（外向き）の集約 | egress の集約 **＋ 検査・制御** |
| 実体 | 自前 VM（要運用） | マネージド | マネージド（専用サブネット） |
| 中身を見るか | 見ない（素通し） | 見ない（SNAT のみ） | **見る**（FQDN/ポート等で許可・拒否） |
| 送信元の書き換え | しない（IP 維持） | する（SNAT） | する（SNAT） |
| next hop の向き先 | 特定スポーク宛て → NVA | （UDR ではなくサブネット関連付け） | `0.0.0.0/0` → Firewall |

## 構成
- **ハブ VNet**: `vnet-hub` (`10.0.0.0/16`)
  - `AzureFirewallSubnet` (`10.0.1.0/26`): **予約名・/26 以上が必須**の Azure Firewall 専用サブネット
- **スポーク VNet**: `vnet-spoke` (`10.1.0.0/16`)
  - `subnet-workload` (`10.1.0.0/24`): 検証用 VM を配置。UDR と `defaultOutboundAccess: false` を適用
- **VNet ピアリング**: `hub ↔ spoke`
- **Public IP**: `pip-azfw` (Standard / Static) … Firewall の出口アドレス（SNAT 先）
- **Azure Firewall**: `azfw` (Standard) + **Firewall Policy** `fw-policy`
  - アプリケーションルール: `api.ipify.org` と `ifconfig.me` だけ許可（それ以外は既定で拒否）
- **UDR**: `rt-spoke` … `0.0.0.0/0` → Firewall のプライベート IP（next hop = VirtualAppliance）
- **VM**: `vm-workload`（パブリック IP なし / Ubuntu 22.04）… 外向き検査の検証対象

## 手順

### 1. リソースのデプロイ

```bash
cd step11
just deploy
```
> **Note**: Azure Firewall のプロビジョニングには **5〜10 分**ほどかかります。

デプロイ後、`just info` で Firewall の公開 IP（出口アドレス）とスポーク VM のプライベート IP を確認できます。

```bash
just info
```

### 2. 許可した FQDN へは出られる＋ SNAT の確認

```bash
just test-allow
```
スポーク VM（パブリック IP なし）から **許可済みの `api.ipify.org`** へ `curl` します。
返ってくる「外から見た送信元 IP」が **Firewall の公開 IP と一致**すれば、外向きが Firewall に集約（SNAT）されていることが確認できます。

### 3. 許可していない FQDN は遮断される

```bash
just test-deny
```
**許可リストにない `www.bing.com`** への `curl` は、Firewall のアプリケーションルールに一致せず**遮断**されます（接続できずエラーになります）。
「IP では届くかどうか」ではなく「**ドメイン名**で出口を制御している」のが本ステップの本質です。

### 4. 経路（UDR）の確認

```bash
just show-routes
```
スポーク VM の NIC の有効ルートに、`0.0.0.0/0 → VirtualAppliance`（Firewall のプライベート IP）のエントリが見えます。これが「全外向きを Firewall に矯正している」実体です。

### 5. Firewall 経由が egress を成立させていることの対比

```bash
just disable-route   # 0.0.0.0/0 → Firewall のルートを削除
just test-allow      # 許可 FQDN でも出られない（出口が無くなる）→ FAIL/TIMEOUT
just enable-route    # ルートを復元
just test-allow      # 再び成功し、egress IP が Firewall の公開 IP に戻る
```
`defaultOutboundAccess: false` のため、UDR を外すと**他に出口が無く**、許可済みの FQDN でも外へ出られなくなります。これにより、egress を成立させているのが **「UDR → Firewall」という経路**であることを切り分けられます（Step1〜10 と同じ「出し入れして因果を確かめる」手法）。

## クリーンアップ

検証が終わったらリソースグループごと削除します。

```bash
just destroy
```
