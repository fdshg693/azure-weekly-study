# Step 7 構成図（Mermaid）

IP 直打ち（Step1〜6）を、**Private DNS Zone による名前解決**に置き換える構成を表現します。

## 1. リソース構成図

VNet を Private DNS Zone `corp.internal` に**リンク**することで、VNet 内の VM が
名前（`vm-b.corp.internal` など）で互いに到達できる。`vm-a`/`vm-b` は自動登録、`app` は手動レコード。

```mermaid
flowchart TD
    PC["あなたの PC<br/>az vm run-command（vm-a 上で実行）"]

    subgraph RG["リソースグループ rg-network-learn-privatedns"]
        NSG["nsg-main<br/>inbound: VirtualNetwork からの ICMP/SSH"]
        subgraph VNet["vnet-privatedns (10.0.0.0/16)"]
            subgraph Sub["subnet-main (10.0.1.0/24)"]
                VMA["vm-a 10.0.1.4<br/>public IP なし"]
                VMB["vm-b 10.0.1.5<br/>public IP なし"]
            end
        end
        subgraph ZONE["Private DNS Zone: corp.internal（VNet 内だけで有効）"]
            R1["vm-a  A 10.0.1.4 ← 自動登録"]
            R2["vm-b  A 10.0.1.5 ← 自動登録"]
            R3["app   A 10.0.1.5 ← 手動レコード"]
        end
    end

    PC -- "ping vm-b.corp.internal" --> VMA
    VMA -- "① 名前を問い合わせ" --> ZONE
    ZONE -- "② 10.0.1.5 を返す" --> VMA
    VMA -- "③ その IP へ ICMP" --> VMB
    VNet -- "link-to-vnet（registration = ON）" --- ZONE
    NSG -. 適用 .-> Sub

    style RG stroke:#9c27b0,stroke-width:2px
    style VNet stroke:#1565c0,stroke-width:2px
    style Sub stroke:#2e7d32,stroke-width:2px
    style ZONE stroke:#00838f,stroke-width:2px
```

## 2. 名前で到達するシーケンス（test-dns）

宛先を IP ではなく**名前**で指定する。VM はまず DNS に問い合わせ、返ってきた IP へ通信する。

```mermaid
sequenceDiagram
    participant PC as あなたの PC (az CLI)
    participant VMA as vm-a (Run Command)
    participant DNS as Azure DNS 168.63.129.16<br/>(corp.internal を解決)
    participant VMB as vm-b 10.0.1.5

    PC->>VMA: ping vm-b.corp.internal を実行
    VMA->>DNS: ① vm-b.corp.internal は？
    DNS-->>VMA: ② 10.0.1.5（リンク済みゾーンの A レコード）
    VMA->>VMB: ③ ICMP を 10.0.1.5 へ
    Note over VMA,VMB: nsg-main が VirtualNetwork からの ICMP を許可
    VMB-->>VMA: ④ 応答 → ping 成功
    Note over PC,VMB: IP を一切打たずに「名前」で到達できた
```

## 3. 自動登録 と 手動レコード

同じゾーンに、機械的な実体名（自動登録）と人が決めた別名（手動）が併存する。

```mermaid
flowchart LR
    subgraph AUTO["自動登録（registrationEnabled = true）"]
        A1["VM 起動 → 自分のホスト名を登録"]
        A2["vm-a → 10.0.1.4<br/>vm-b → 10.0.1.5"]
        A1 --> A2
    end
    subgraph MAN["手動レコード"]
        M1["人が別名を IP に向ける"]
        M2["app → 10.0.1.5（=vm-b の別名）"]
        M1 --> M2
    end
```

## 4. シナリオ: リンクを外すと「名前は引けないが IP では届く」

`just unlink` でリンクを削除すると名前解決だけが壊れる。経路（IP 到達性）は不変。
→ 名前で届いていたのは Private DNS Zone のおかげだと切り分けられる（NSG/UDR の出し入れと同じ手法）。

```mermaid
sequenceDiagram
    participant VMA as vm-a
    participant DNS as Azure DNS
    participant VMB as vm-b 10.0.1.5

    Note over VMA,VMB: リンクあり（just test-dns 成功）
    VMA->>DNS: vm-b.corp.internal は？
    DNS-->>VMA: 10.0.1.5
    VMA->>VMB: ICMP → 到達

    Note over VMA,VMB: just unlink 実行後
    VMA->>DNS: vm-b.corp.internal は？
    DNS--xVMA: 解決できない（VNet からゾーンが見えない）→ test-dns 失敗
    Note over VMA,VMB: ただし just test-ip（10.0.1.5 直打ち）は依然 成功
    VMA->>VMB: ICMP → 到達（経路は無傷）
```
