# Step 1 構成図（Mermaid）

このステップのネットワーク構成と、通信シナリオを Mermaid で表現します。

## 1. リソース構成図

VM はネットワークに直接つながらず、NIC を介してサブネットに所属します。
NSG は**サブネット**に適用され、受信通信を判定します。

```mermaid
flowchart TD
    Local["ローカル PC"]
    Internet(("インターネット"))

    subgraph RG["リソースグループ rg-network-learn-minimal"]
        PIP["パブリック IP<br/>pip-vm-minimal"]
        NSG{{"NSG nsg-minimal<br/>(サブネットに適用)"}}
        subgraph VNet["VNet vnet-minimal (10.0.0.0/16)"]
            subgraph Subnet["サブネット subnet-default (10.0.0.0/24)"]
                NIC["NIC nic-vm-minimal<br/>private 10.0.0.x"]
                VM["VM vm-minimal<br/>Ubuntu 22.04"]
            end
        end
    end

    Local --> Internet --> PIP
    PIP -. "Azure ホストが自動で 1:1 NAT<br/>(受信=DNAT: public → private)" .-> NIC
    NSG -. "受信ルールを判定" .-> Subnet
    NIC --> VM

    style RG stroke:#9c27b0,stroke-width:2px
    style VNet stroke:#1565c0,stroke-width:2px
    style Subnet stroke:#e65100,stroke-width:2px
```

> パブリック IP は独立した箱ではなく **NIC に紐づく属性**。NIC は「外向きの顔（public IP）」と「内向きの顔（private IP）」を 1 枚で持つ。

### NAT（アドレス変換）について — 誤解しないための補足

* **NAT とは**: パケットが通過する途中で **IP アドレスを書き換える**仕組み。
  * **DNAT**（宛先変換）: 受信時に「宛先＝パブリック IP」を「プライベート IP」へ書き換える。
  * **SNAT**（送信元変換）: 送信時に「送信元＝プライベート IP」を「パブリック IP」へ書き換える。
* **この変換は自動**: パブリック IP を NIC に関連付けるだけで、Azure が受信(DNAT)・送信(SNAT)の **1:1 NAT を自動で行う**。NAT ルールを自分で書く必要はない。
  * トリガーは `main.bicep` の NIC 設定 `ipConfigurations[].properties.publicIPAddress` への関連付けだけ。
* **変換するのは VM ではなく Azure ホスト側**: 実際の書き換えは VM の外（物理ホスト上の仮想スイッチ / SDN レイヤ）で行われる。
  * そのため **VM の OS はパブリック IP を一切知らない**。VM 内で `ip addr` を見てもプライベート IP しか出てこない。
* **「DNAT を設定する」別ケースとの違い**: Load Balancer のインバウンド NAT 規則、Azure Firewall / NVA の DNAT、NAT Gateway などは**ルールを明示的に定義**する。今回（NIC に直接パブリック IP）は、それらと違って**設定不要の自動 NAT**である点に注意。

## 2. NSG の受信ルール評価（priority 順）

```mermaid
flowchart TD
    Start["受信パケット到着"] --> R100{"priority 100<br/>Allow-ICMP-Inbound?"}
    R100 -- "ICMP 一致" --> AllowICMP["許可"]
    R100 -- "不一致" --> R110{"priority 110<br/>Allow-SSH-Inbound?"}
    R110 -- "TCP/22 一致" --> AllowSSH["許可"]
    R110 -- "不一致" --> Default["既定 DenyAllInBound (65500)"]
    Default --> Deny["拒否"]
```

> priority の小さいルールから評価され、最初に一致したルールで決まる。明示的に Allow しない通信は最後の `DenyAllInBound` で拒否される。

## 3. シナリオ: ping の許可 / 拒否

`just deny-ping` で ICMP ルールを Deny にすると、サブネット境界の NSG でパケットが破棄される（VM/OS は無変更）。

```mermaid
sequenceDiagram
    participant L as ローカル PC
    participant P as パブリック IP
    participant N as NSG (サブネット)
    participant V as VM

    Note over L,V: シナリオ A: ICMP Allow（既定）
    L->>P: ICMP Echo Request (宛先 public IP)
    P->>N: 自動 DNAT で private IP へ変換して転送
    N->>V: Allow-ICMP-Inbound に一致 → 通過
    V-->>L: Echo Reply（疎通成功）

    Note over L,V: シナリオ B: just deny-ping 実行後
    L->>P: ICMP Echo Request
    P->>N: 自動 DNAT で private IP へ変換して転送
    N--xV: ICMP ルールが Deny → 破棄
    Note over L: 応答なし（タイムアウト）
```
