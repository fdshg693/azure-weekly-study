# Step3 (advanced): オンプレ／拠点間をつなぐ — VPN Gateway / IPsec / BGP

このステップは `PLAN.md` の **案1** を実装したものです。
basic/step2（ピアリング＝同一クラウド内の VNet 接続）と basic/step3（UDR の静的経路）の発展として、
**物理的に離れた拠点同士を、公衆インターネット越しの暗号化トンネルでつなぎ**、
さらに **BGP で経路を自動的に交換する**「ハイブリッド接続の中核」を学びます。

## このステップで解く問題（まず一般概念）

- **ピアリングは「同じクラウド内の私設配線」** でした。これに対し、オンプレや別拠点は物理的に離れていて、
  間には**公衆インターネット**しかありません。そこを安全に通すには、**暗号化トンネル（IPsec）** を張ります。
- トンネルが張れても、**「相手側にどんなネットワーク（プレフィックス）があるか」を経路表に教えないと通信できません**。
  basic/step3 ではこれを **UDR で手書き**しました。拠点が増えるたび、両側で手作業が必要になり破綻します。
- そこで **BGP（動的ルーティング）**：トンネル上でルータ同士が「自分の持つネットワークはこれ」と**広告し合い、
  経路を自動で学習**します。アドレス空間を足しても、手で UDR を書き直さずに相手へ伝わります。

> このステップの肝は **「トンネル（到達経路の確保）」と「BGP（経路の自動伝播）」は別の関心事**だと体で分けることです。

## Azure 実現

- 検証用の "オンプレ" は用意できないので、**別の VNet ＋ 別の VPN Gateway** で代用します（**VNet-to-VNet** 接続）。
  - `vnet-hub` (`10.0.0.0/16`) … Azure 側の拠点
  - `vnet-onprem` (`10.50.0.0/16`) … "オンプレ" 役の拠点
- 各 VNet の **`GatewaySubnet`** に **VPN Gateway（VpnGw1 / RouteBased / BGP 有効）** を置きます。
- 2 つのゲートウェイを **VNet-to-VNet 接続（IPsec/IKE・事前共有鍵）** で双方向に結びます。
- 両ゲートウェイに**異なる ASN**（hub=65515 / onprem=65501）を割り当て、トンネル上で **BGP セッション**を張ります。
- 各拠点にテスト VM（Nginx・公開 IP なし）を置き、**`az vm run-command`** で VM の "内側" から
  対向 VM の private IP へ `curl` して疎通を確かめます（SSH の口を開けません）。

> 学習手法は basic と同じ ―― 「設定を出し入れして、通信の変化から因果を確かめる」。
> 出し入れするスイッチは **①トンネル up/down** と **②BGP の経路伝播（プレフィックス追加）** の 2 つです。

## ⚠ コスト注意（重要）

**VPN Gateway は時間課金が高い**リソースです（VpnGw1 は 1 台あたり概ね $0.04〜0.19/時、本ステップは **2 台**）。
さらにプロビジョニングに **1 台 30〜45 分**かかります。**検証が終わったら必ず `just cleanup`** してください。
出しっぱなしが最もコスト事故につながる構成です。

## ファイル構成（Bicep はモジュール分割）

```
step3/
├── main.bicep              … オーケストレータ（site/gateway/connection を 2 回ずつ呼ぶ）
└── modules/
    ├── site.bicep          … 1 拠点分: VNet(GatewaySubnet+workload)・NSG・テスト VM
    ├── gateway.bicep       … 1 つの VPN Gateway（Public IP + BGP 設定）
    └── connection.bicep    … VNet-to-VNet 接続（IPsec・PSK・BGP 有効）
```

## 構成

- **VNet / Gateway**
  | 拠点 | VNet | GatewaySubnet | workload | VPN Gateway | ASN | test VM |
  | --- | --- | --- | --- | --- | --- | --- |
  | hub | `10.0.0.0/16` | `10.0.255.0/27` | `10.0.1.0/24` | `vng-hub` (VpnGw1) | 65515 | `vm-hub` (`10.0.1.4`) |
  | onprem | `10.50.0.0/16` | `10.50.255.0/27` | `10.50.1.0/24` | `vng-onprem` (VpnGw1) | 65501 | `vm-onprem` (`10.50.1.4`) |
- **接続**: `conn-hub-to-onprem` / `conn-onprem-to-hub`（VNet-to-VNet・IPsec・PSK 共有・**BGP 有効**）
- **NSG**: 各 workload サブネットで、**対向拠点のアドレス空間からの HTTP/80 と ICMP** を許可（GatewaySubnet には付けない）

## 前提

- `az` CLI（ログイン済み）、`just`。拡張機能は不要。
- 疎通確認は `az vm run-command` を使うため、テスト VM に公開 IP・SSH は不要です。

## 手順

### 1. デプロイ（30〜45 分かかります）

```bash
cd advanced/step3
just deploy
```

VPN Gateway 2 台の作成に時間がかかります。完了後 `just info` で接続状態が `Connected` になっていることを確認します
（デプロイ直後はトンネル確立まで数分ラグがあることがあります）。

### 2. トンネル越しに届くことの確認

```bash
just test
```

```text
From vm-hub -> curl http://10.50.1.4/ (トンネル越し)
Reached vm-onprem (private-ip 10.50.1.4)
```

hub 拠点の VM から、**離れた onprem 拠点の private IP へ、暗号化トンネル越しに到達**できています。
逆方向は `just test-reverse`。

### 3. BGP が経路を「学習している」ことの確認（動的ルーティングの核心）

```bash
just bgp-status      # 対向 ASN とのセッションが state=Connected か
just learned-routes  # BGP で伝播してきた経路一覧
```

`learned-routes` に **`10.50.0.0/16` が `origin=EBgp`／`nextHop=対向の BGP ピア IP`** で出ていれば、
この経路は **手書き（UDR）ではなく BGP が自動で運んできた**証拠です。
basic/step3 では UDR を手で書きましたが、ここでは**何も書いていないのに経路が入っている**点が決定的な違いです。

### 4. 【出し入れ①】トンネル up/down で「経路が消える／復活する」

```bash
just tunnel-down       # 双方向の接続を削除
# 数十秒後:
just test              # → TIMEOUT/UNREACHABLE（届かなくなる）
just learned-routes    # → 10.50.0.0/16 が消える（経路が引っ込む）

just tunnel-up         # 接続を双方向に再作成（BGP 有効・同じ PSK）
# 1〜2 分後（bgp-status が Connected になってから）:
just test              # → 再び 200
just learned-routes    # → 経路が復活
```

到達を成立させているのが **トンネルと、その上の経路交換**であることが切り分けられます。

### 5. 【出し入れ②】BGP の真価 ― 新プレフィックスの自動伝播

BGP の値は「拓ったトンネルで通る」ことより、**構成変更が自動で相手に伝わる**ことにあります。

```bash
just add-prefix        # vnet-onprem に 10.60.0.0/16 を追加（経路は一切手書きしない）
# 1〜2 分後:
just learned-routes    # → hub 側に 10.60.0.0/16 が EBgp で自動的に現れる

just del-prefix        # 元に戻すと learned-routes からも消える
```

**静的 UDR なら、対向の新ネットワークを手で経路表に足さねば届きません。**
BGP では VNet にアドレス空間を足しただけで相手側へ広告される ―― これが規模が増えても破綻しない理由です。

## basic との対比

| 観点 | basic/step2 (ピアリング) | basic/step3 (UDR) | 本ステップ (VPN + BGP) |
| --- | --- | --- | --- |
| 接続の性質 | 同一クラウド内の私設配線 | （経路制御のみ） | **公衆網越しの暗号化トンネル(IPsec)** |
| 経路の入り方 | 自動（同一バックボーン） | **手書きの静的経路** | **BGP で動的に学習・伝播** |
| 構成変更時 | ― | 両側で UDR を手修正 | **アドレス空間を足すだけで自動広告** |
| 出し入れスイッチ | ピアリング有無 | UDR 有効/無効 | **トンネル up/down ＋ プレフィックス追加** |

## クリーンアップ（必ず実行）

```bash
just cleanup
```

VPN Gateway は時間課金が高いため、削除が完了するまで見届けてください。
