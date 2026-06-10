# Step 2 構成図（Mermaid）

VNet ピアリングで 2 つの独立した VNet を接続し、VM 同士がプライベート IP で通信する構成を表現します。

## 1. リソース構成図

vm-1 はパブリック IP あり（入口）、vm-2 はパブリック IP なし（隔離）。
2 つの VNet は双方向のピアリングで接続される。

```mermaid
flowchart LR
    Local["ローカル PC"]
    Internet(("インターネット"))

    subgraph RG["リソースグループ rg-network-learn-peering"]
        PIP["パブリック IP<br/>pip-vm1"]
        NSG1{{"nsg-vnet1<br/>src: * (どこからでも)"}}
        NSG2{{"nsg-vnet2<br/>src: 10.1.0.0/24 のみ"}}
        subgraph VNet1["VNet vnet-1 (10.1.0.0/16)"]
            subgraph Sub1["subnet-1 (10.1.0.0/24)"]
                VM1["vm-1<br/>private 10.1.0.x<br/>public あり"]
            end
        end
        subgraph VNet2["VNet vnet-2 (10.2.0.0/16)"]
            subgraph Sub2["subnet-2 (10.2.0.0/24)"]
                VM2["vm-2<br/>private 10.2.0.x<br/>public なし"]
            end
        end
    end

    Local --> Internet --> PIP --> VM1
    VM1 <-- "VNet ピアリング<br/>(双方向 / プライベート通信)" --> VM2
    NSG1 -. 適用 .-> Sub1
    NSG2 -. 適用 .-> Sub2

    style RG stroke:#9c27b0,stroke-width:2px
    style VNet1 stroke:#1565c0,stroke-width:2px
    style VNet2 stroke:#1565c0,stroke-width:2px
    style Sub1 stroke:#e65100,stroke-width:2px
    style Sub2 stroke:#e65100,stroke-width:2px
```

## 2. ピアリングは双方向に 2 つ定義する

片方だけでは状態が `Initiated` のまま。両方そろって `Connected` になり通信が成立する。

```mermaid
flowchart LR
    subgraph V1["vnet-1"]
        P1["peering-vnet1-to-vnet2<br/>parent: vnet1<br/>remote: vnet2"]
    end
    subgraph V2["vnet-2"]
        P2["peering-vnet2-to-vnet1<br/>parent: vnet2<br/>remote: vnet1"]
    end
    P1 -- "vnet1 → vnet2 を見にいく" --> V2
    P2 -- "vnet2 → vnet1 を見にいく" --> V1

    style V1 stroke:#1565c0,stroke-width:2px
    style V2 stroke:#1565c0,stroke-width:2px
```

> 両ピアリングとも `allowVirtualNetworkAccess=true` のみ有効化し、forwarded / gatewayTransit / useRemoteGateways は false（最小構成）。

## 3. シナリオ: 経路がプライベートであることの二重の担保

```mermaid
sequenceDiagram
    participant L as ローカル PC
    participant V1 as vm-1 (10.1.0.x)
    participant V2 as vm-2 (10.2.0.x)

    Note over V1,V2: シナリオ A: just test-peering（成功）
    Note over V1: Run Command で vm-1 内部から実行
    V1->>V2: ICMP（ピアリング経由・private IP 宛て）
    Note over V2: nsg2 が src 10.1.0.0/24 を許可
    V2-->>V1: Echo Reply（疎通成功）

    Note over L,V2: シナリオ B: just test-local-fail（失敗）
    L--xV2: ローカルから vm-2 の private IP へ ping
    Note over V2: public IP 無し → インターネットから到達不能
    Note over L: タイムアウト
```

> A が成功し B が失敗することで、成功した通信が確実に **VNet ピアリング経由のプライベート通信**であることを担保する。さらに nsg2 で送信元を subnet-1 に限定し、NSG レベルでも裏付けている。
