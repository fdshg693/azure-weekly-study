# Step 5 で登場した用語・概念

このステップで**新たに**登場した用語・概念をまとめます。
VNet・サブネット・NSG・VM・パブリック IP の有無による隔離・送信元限定（最小権限）・
踏み台／多段 SSH（`ssh -J`）・公開鍵認証など、Step 1〜4 でカバーした内容は前提として含めません。

## ネットワーク全般の概念

### egress（外向き通信）と「inbound と outbound は別物」
* **egress（イーグレス）= 外向き（送信）の通信**、**ingress（イングレス）= 内向き（受信）の通信**。
* パブリック IP を持たないホストは、インターネットから**受信する入口を持たない**。だが OS 更新・パッケージ取得・外部 API 呼び出しなど、**自分から外へ出る（egress）通信**は普通に必要になる。
* ここでの肝は **「inbound を閉じる」と「outbound を許す」は別レイヤの設定**であること。
  * inbound を閉じる手段：パブリック IP を付けない／NSG の inbound ルールで送信元を絞る。
  * outbound を許す手段：サブネットに**出口（NAT Gateway 等）**を用意する。
* 受信は一切開けないまま、送信だけは成立させられる。本ステップの private VM がまさにそれ（踏み台越しの SSH 以外は受け付けないが、外へは出られる）。

### SNAT（送信元 NAT）と「出口の集約」
* **SNAT（Source NAT）= 送信元アドレスの変換**。プライベート IP を持つホストが外へ出るとき、パケットの**送信元 IP を、外部で通用するパブリック IP に書き換える**。
* 複数のプライベートホストの送信を、**1 つ（少数）のパブリック IP に集約**できる。外部のサーバから見ると、それらホストは**すべて同じ送信元 IP（出口の IP）から来たように見える**。
  * 本ステップで `curl https://api.ipify.org` の結果が NAT Gateway のパブリック IP に一致するのは、この SNAT のため。
* SNAT は**一方向（送信側）の仕組み**：内部ホストが起点となって張った接続の戻りパケットは通すが、**外部から内部への新規接続の入口にはならない**。だから「出口はあるが入口は無い」を実現できる。
  * 家庭用ルータが LAN 内の複数端末を 1 つのグローバル IP で外に出すのと同じ発想（あちらは NAPT/PAT）。
* 戻り通信を正しく内部ホストへ返すため、SNAT 機構は送信時に**送信元ポートを割り当てて対応付け**を覚える（コネクション追跡）。使えるポート数には上限があり、これが egress の同時接続数の上限になる。

### 「経路（出口があるか）」と「許可（NSG）」はやはり別物
* Step3 で「経路（ルーティング）」と「許可（NSG）」は別レイヤだと学んだが、egress でも同じ構図。
  * NSG の outbound ルールを許可していても、**出口（NAT Gateway 等）が無ければ外へは出られない**。
  * 逆に出口があっても、NSG の outbound で拒否すれば出られない。
* つまり egress の成立には「**NSG が許す（許可）**」かつ「**出口がある（経路）**」の両方が要る。本ステップは後者（出口の有無）を NAT Gateway の付け外しで確認している。

## Azure 固有の用語（上記概念の具体例）

### NAT Gateway（マネージドな送信専用の出口）
* **NAT Gateway** は、サブネットに関連付けると、そのサブネット内の全ホストの **outbound を 1 つのパブリック IP に集約（SNAT）する**マネージドサービス。
  * サブセットに付ける（NIC ではなくサブネット単位）。サブネット内の VM は設定不要で、自動的にこの出口を使うようになる。
  * **inbound の宛先にはならない**：Load Balancer（Step 候補 B）のように外から接続を受ける入口ではなく、純粋に「送信の出口」専用。
* **Standard SKU のパブリック IP が必須**（本ステップは `pip-natgw` を静的割り当てで用意）。出口の IP が固定されるので、相手側のファイアウォール許可リストに載せやすい、という実務上の利点もある。
* SNAT のポートを大量に確保でき（PIP 1 つあたり多数）、Load Balancer のアウトバウンド規則より**ポート枯渇に強い**のが Azure 公式の推奨理由。本ステップでは「private VM の素直な出口」として使う。

### サブネットへの NAT Gateway 関連付け（`natGateway` プロパティ）と付け外し
* Bicep ではサブネットの `properties.natGateway.id` に NAT Gateway の ID を指定して関連付ける。
* CLI では `az network vnet subnet update ... --nat-gateway <名前>` で関連付け、`--remove natGateway` で関連付けを外せる。
  * 本ステップの `just detach-nat` / `attach-nat` がこれ。**外す → 外へ出られない、戻す → 出られる**、という対比で「egress を成立させているのは NAT Gateway」だと確認する（Step4 の `lock-private` / `unlock-private` と同じ「設定を出し入れして因果を確かめる」手法）。

### 既定の送信アクセス（default outbound access）の無効化（`defaultOutboundAccess: false`）
* Azure には従来、明示的な出口（NAT Gateway や Load Balancer のアウトバウンド規則、インスタンスのパブリック IP）が無くても、**Azure が暗黙に提供する共有 SNAT で外へ出られる**「既定の送信アクセス」という挙動があった。
* これを有効のままにすると、**NAT Gateway を外しても暗黙の出口で外に出られてしまい**、「NAT Gateway が egress を成立させている」という対比がぼやける。
* そこで `subnet-private` で **`defaultOutboundAccess: false`** を指定し、暗黙の出口を無効化している。これにより「**出口は NAT Gateway だけ**」になり、外すと確実に egress が止まる＝本ステップの検証が成立する。
* なお Azure は既定の送信アクセスを**将来廃止する方針**で、出口を NAT Gateway 等で**明示するのが今後の推奨**でもある。学習用の対比であると同時に、実務の作法としても妥当。

### private VM にパブリック IP を付けないことの意味（再掲・本ステップ視点）
* Step4 では「パブリック IP が無い＝直接は入れない（inbound を閉じる）」ことを確認した。
* 本ステップでは同じ「パブリック IP なし」を **outbound の視点**で見る：もしパブリック IP を付けると、その IP 自身で外へ出られてしまい、NAT Gateway の有無による対比が成立しない。
* パブリック IP を付けないことで、「**受信の入口は無いが、送信の出口（NAT Gateway）はある**」という非対称を、1 台の VM できれいに観察できる。

## なぜ private VM が「外へは出られるが、外からは入れない」のか（経路の全体像）

`vm-private (10.0.1.x、パブリック IP なし)` から `https://api.ipify.org` への外向き通信の例。

```
[vm-private 10.0.1.x / public IP なし]
   │ ① 外向きパケットを送出（送信元 = 自分のプライベート IP）
   │    → nsg-private の outbound：拒否ルールは無い ⇒ 許可（NSG レイヤは通す）
   ▼
[subnet-private の出口判定]
   │ ② このサブネットには NAT Gateway が関連付けられている ⇒ 出口あり
   │    （defaultOutboundAccess=false なので、出口は NAT Gateway だけ）
   ▼
[NAT Gateway natgw / pip-natgw]
   │ ③ SNAT：送信元 IP を pip-natgw に書き換え、ポートを割り当てて対応付けを記録
   ▼
[インターネット]
   │ ④ 外部サーバから見た送信元 = pip-natgw（だから ipify は pip-natgw を返す）
   ▼
[戻りパケット]
   ⑤ NAT Gateway が ③ の対応付けを引いて vm-private へ戻す（外部発の "新規" 接続ではないので通る）

一方、外部からの "新規" 受信：
   ✗ vm-private にパブリック IP は無く、NAT Gateway も入口にはならない ⇒ そもそも到達不能
```

### 各段階で何がそれを可能にしているか

| 段階 | 可能にしている設定 | これが無いと |
|------|-------------------|-------------|
| ① NSG を通る | nsg-private に outbound 拒否が無い | 出口があっても NSG で送信が止まる |
| ② 出口がある | **subnet-private への NAT Gateway 関連付け** | 外へ出られない（`detach-nat` で再現できる） |
| （②の前提） | **defaultOutboundAccess=false** | 暗黙の送信アクセスで出てしまい、NAT Gateway の効果が見えない |
| ③④ SNAT | NAT Gateway + **pip-natgw（Standard）** | 送信元を変換する出口の IP が無く外で通用しない |
| 入口が無い | **パブリック IP なし**＋NAT Gateway は inbound にならない | 外から直接入れてしまい「出口だけ」が成立しない |

## このステップの要点
* **egress（外向き）と ingress（内向き）は別物**。パブリック IP を持たない VM でも、出口さえあれば外へは出られる。「inbound を閉じる」と「outbound を許す」は別レイヤの設定。
* **SNAT** は内部ホストの送信元 IP を出口のパブリック IP に書き換え、複数ホストの送信を 1 つの出口に集約する。外から見た送信元はその出口の IP になる（`curl ipify` の結果が NAT Gateway の IP と一致する）。SNAT は送信起点の戻り通信は通すが、**外からの新規接続の入口にはならない**。
* **NAT Gateway** はサブネットに付ける**送信専用のマネージドな出口**。inbound の宛先にはならず、Standard パブリック IP を出口として使う。
* **`defaultOutboundAccess: false`** で Azure の暗黙の送信アクセスを無効化し、「出口＝NAT Gateway だけ」にすることで、付け外しによる egress の成立／不成立の対比をクリアにしている（Azure 自身も既定の送信アクセスは将来廃止＝出口の明示が推奨）。
* `just detach-nat` / `attach-nat` で出口を出し入れすると、outbound だけが止まる／復活し、inbound（踏み台越しの SSH）は終始変わらない。これが「inbound と outbound は別物」「egress を成立させているのは NAT Gateway」の何よりの確認になる。
