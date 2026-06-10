# Step 5 構成図（Mermaid）

パブリック IP を持たない private VM の **外向き通信（egress / SNAT）** を NAT Gateway で成立させる構成を表現します。

## 1. リソース構成図

private VM はパブリック IP を持たない（＝受信の入口が無い）が、サブネットに付けた **NAT Gateway** が
**送信専用の出口**になる。踏み台は確認のための入口で、主役は private VM の egress。

```mermaid
flowchart TD
    PC["あなたの PC"]
    NET["インターネット"]

    subgraph RG["リソースグループ rg-network-learn-natgw"]
        NSGB["nsg-bastion<br/>SSH 許可: 自分の IP /32 のみ"]
        NSGP["nsg-private<br/>inbound: 10.0.0.0/24 のみ<br/>outbound: 拒否なし"]
        subgraph VNet["vnet-natgw (10.0.0.0/16)"]
            subgraph SubB["subnet-bastion (10.0.0.0/24) = 公開ゾーン"]
                BAS["vm-bastion 10.0.0.4<br/>public IP あり（確認用の入口）"]
            end
            subgraph SubP["subnet-private (10.0.1.0/24) = 非公開ゾーン<br/>defaultOutboundAccess = false"]
                PRIV["vm-private 10.0.1.x<br/>public IP なし"]
                NAT["NAT Gateway natgw<br/>+ pip-natgw（出口の public IP）<br/>送信専用 / inbound にはならない"]
            end
        end
    end

    PC -- "SSH(22) 自分の IP からのみ" --> BAS
    BAS -- "ssh -J で中継（確認用）" --> PRIV
    PRIV -- "outbound（送信）" --> NAT
    NAT -- "SNAT 後に外へ（src = pip-natgw）" --> NET
    NSGB -. 適用 .-> SubB
    NSGP -. 適用 .-> SubP

    style RG stroke:#9c27b0,stroke-width:2px
    style VNet stroke:#1565c0,stroke-width:2px
    style SubB stroke:#e65100,stroke-width:2px
    style SubP stroke:#2e7d32,stroke-width:2px
    style NAT stroke:#00838f,stroke-width:2px
```

## 2. 「inbound を閉じる」と「outbound を許す」は別物

同じ private VM でも、受信（ingress）と送信（egress）は別レイヤ。
受信の入口は一切無いのに、送信の出口（NAT Gateway）は持てる、という非対称を 1 台で観察する。

```mermaid
flowchart LR
    NET["インターネット"]
    subgraph P["vm-private（public IP なし）"]
        IN["ingress（受信）<br/>入口なし"]
        OUT["egress（送信）<br/>出口あり"]
    end
    NAT["NAT Gateway<br/>pip-natgw"]

    NET -. "新規接続は到達不能（×）<br/>public IP なし / NAT は入口にならない" .-> IN
    OUT -- "送信は成立（○）" --> NAT
    NAT -- "src を pip-natgw に SNAT" --> NET
    NAT -- "戻りパケットだけ private へ返す" --> OUT
```

## 3. SNAT の流れ — 外から見た送信元は「出口の IP」になる

`vm-private` が `https://api.ipify.org` に問い合わせると、返ってくる送信元 IP は
NAT Gateway のパブリック IP（`pip-natgw`）。`just test-egress` でこの一致を確認する。

```mermaid
sequenceDiagram
    participant P as vm-private 10.0.1.x (public IP なし)
    participant N as NAT Gateway (pip-natgw)
    participant I as api.ipify.org

    P->>N: ① 送信（src = 10.0.1.x プライベート）
    Note over N: ② SNAT：src を pip-natgw に書換え<br/>ポートを割り当てて対応付けを記録
    N->>I: ③ 外へ（src = pip-natgw）
    I-->>N: ④ 「あなたの IP は pip-natgw です」
    N-->>P: ⑤ 対応付けを引いて private へ戻す
    Note over P: curl の結果 = pip-natgw<br/>＝出口（SNAT）に集約されている証拠
```

## 4. シナリオ: NAT Gateway を出し入れすると outbound だけが変わる

`just detach-nat` / `attach-nat` で、外へ出られていたのが **NAT Gateway（出口）** だと確認する。
このとき **inbound（踏み台越し SSH）は終始変わらない**点が「inbound と outbound は別物」の証拠。

```mermaid
sequenceDiagram
    participant P as vm-private
    participant S as subnet-private
    participant I as インターネット

    Note over P,I: NAT Gateway あり（just test-egress 成功）
    P->>S: 外向きパケット
    S->>I: NAT Gateway 経由で SNAT → 到達
    I-->>P: 応答（egress IP = pip-natgw）

    Note over P,I: just detach-nat 実行後（defaultOutboundAccess=false）
    P->>S: 外向きパケット
    S--xP: 出口が無い → egress 失敗（タイムアウト）
    Note over P: ※踏み台越しの SSH(inbound) はこの間も通る<br/>＝止まったのは outbound だけ
```

## 5. Step3 の NVA / Step4 の踏み台 / Step5 の NAT Gateway の違い

いずれも「内部ホストの通信を別の経路に通す」が、役割が異なる。

```mermaid
flowchart TD
    subgraph NVA["Step3: NVA（L3 中継ルーター）"]
        A["spoke 間の通信を転送<br/>NAT しない（送信元は元のまま）"]
    end
    subgraph BAS["Step4: 踏み台（L7 jump box）"]
        B["人/鍵の中継点（inbound 側）<br/>private への入口を 1 つに集約"]
    end
    subgraph NAT["Step5: NAT Gateway（egress / SNAT）"]
        C["private の出口を 1 つに集約（outbound 側）<br/>SNAT する / inbound にはならない"]
    end
```
