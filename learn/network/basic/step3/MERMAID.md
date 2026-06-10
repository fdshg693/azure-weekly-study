# Step 3 構成図（Mermaid）

Hub-Spoke 構成と UDR による spoke 間ルーティングを表現します。

## 1. リソース構成図

ハブに NVA（中継ルーター）を置き、各スポークはハブとだけピアリングする。
**spoke1 ↔ spoke2 は直接ピアリングしない**。各スポークの UDR が「相手 spoke 宛ては NVA 経由」と経路を上書きする。

```mermaid
flowchart TD
    subgraph RG["リソースグループ rg-network-learn-hubspoke"]
        subgraph Hub["vnet-hub (10.0.0.0/16)"]
            subgraph SubNva["subnet-nva (10.0.0.0/24)"]
                NVA["vm-nva / NVA<br/>10.0.0.4 (固定)<br/>IP forwarding 有効"]
            end
        end
        RT1["rt-spoke1<br/>10.2.0.0/16 → NVA"]
        RT2["rt-spoke2<br/>10.1.0.0/16 → NVA"]
        subgraph Spoke1["vnet-spoke1 (10.1.0.0/16)"]
            subgraph SubS1["subnet-spoke1 (10.1.0.0/24)"]
                VM1["vm-spoke1<br/>10.1.0.x / public あり"]
            end
        end
        subgraph Spoke2["vnet-spoke2 (10.2.0.0/16)"]
            subgraph SubS2["subnet-spoke2 (10.2.0.0/24)"]
                VM2["vm-spoke2<br/>10.2.0.x / public なし"]
            end
        end
    end

    Hub <-- "peering (forwarded 許可)" --> Spoke1
    Hub <-- "peering (forwarded 許可)" --> Spoke2
    Spoke1 -. "spoke1 ↔ spoke2 は<br/>直接ピアリング無し（✕）" .- Spoke2
    RT1 -. 適用 .-> SubS1
    RT2 -. 適用 .-> SubS2

    style RG stroke:#9c27b0,stroke-width:2px
    style Hub stroke:#1565c0,stroke-width:2px
    style Spoke1 stroke:#1565c0,stroke-width:2px
    style Spoke2 stroke:#1565c0,stroke-width:2px
    style SubNva stroke:#e65100,stroke-width:2px
    style SubS1 stroke:#e65100,stroke-width:2px
    style SubS2 stroke:#e65100,stroke-width:2px
```

## 2. spoke1 → spoke2 の通信経路（UDR + NVA 経由）

直接の経路は無いが、UDR が next hop を NVA に向けることで通信が成立する。

```mermaid
flowchart LR
    VM1["vm-spoke1<br/>10.1.0.4"]
    UDR1{"rt-spoke1<br/>10.2/16 → NVA?"}
    NVA["NVA 10.0.0.4<br/>転送 (NAT しない)"]
    NSG2{"nsg-spoke2<br/>src 10.1.0.0/24 許可?"}
    VM2["vm-spoke2<br/>10.2.0.4"]

    VM1 --> UDR1 -- "next hop = NVA" --> NVA
    NVA -- "hub↔spoke2 peering<br/>allowForwardedTraffic=true" --> NSG2
    NSG2 -- "src は元のまま 10.1.0.4" --> VM2
    VM2 -. "戻りは rt-spoke2 (10.1/16 → NVA) で同経路を逆走" .-> NVA
```

## 3. NVA が「ルーター化」する二段構え

NIC（Azure 層）と OS（カーネル層）の両方で転送を許可して初めて中継できる。

```mermaid
flowchart TD
    P["自分宛てでないパケットが到着"]
    A{"NIC: enableIPForwarding<br/>= true ?"}
    O{"OS: net.ipv4.ip_forward<br/>= 1 ?"}
    F["経路表に従って転送"]
    D["破棄"]

    P --> A
    A -- いいえ --> D
    A -- はい --> O
    O -- いいえ --> D
    O -- はい --> F
```

## 4. シナリオ: UDR の有無で通信が変わる

`just disable-route` / `enable-route` で、経路を成立させているのが**ピアリングではなく UDR**だと確認できる。

```mermaid
sequenceDiagram
    participant V1 as vm-spoke1
    participant U as rt-spoke1 (UDR)
    participant N as NVA (10.0.0.4)
    participant V2 as vm-spoke2

    Note over V1,V2: シナリオ A: UDR あり（just test-peering 成功）
    V1->>U: 宛先 10.2.0.4
    U->>N: next hop = NVA
    N->>V2: 転送（forwarded 許可 + NSG 許可）
    V2-->>V1: Echo Reply（NVA 経由で成功）

    Note over V1,V2: シナリオ B: just disable-route 実行後
    V1->>U: 宛先 10.2.0.4
    Note over U: 10.2/16 の経路が無い
    U--xV2: 宛先不明 → デフォルトルートで破棄
    Note over V1: タイムアウト（ピアリングだけでは届かない）
```

> `just trace-route`（tracepath）で経路上に NVA(10.0.0.4) が hop として現れることからも、直接ではなく NVA を経由していることが確認できる。
