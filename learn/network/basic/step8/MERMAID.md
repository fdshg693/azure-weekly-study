# Step 8 構成図（Mermaid）

PaaS（Storage/blob）へ、公衆インターネットを経由せず **VNet 内のプライベート IP** で到達する構成
（**Private Endpoint** + **Private DNS Zone**）を表現します。

## 1. リソース構成図

公開 FQDN `<account>.blob.core.windows.net` は、リンク済み VNet 内では Private DNS Zone により
Private Endpoint のプライベート IP（`10.0.1.x`）に解決される。Storage の公開エンドポイントは閉じてある。

```mermaid
flowchart TD
    PC["あなたの PC<br/>az vm run-command（vm 上で実行）"]

    subgraph RG["リソースグループ rg-network-learn-privatelink"]
        subgraph VNet["vnet-privatelink (10.0.0.0/16)"]
            subgraph SubVm["snet-vm (10.0.2.0/24)"]
                VM["vm 10.0.2.4<br/>public IP なし"]
            end
            subgraph SubPe["snet-pe (10.0.1.0/24)"]
                PE["pe-blob NIC<br/>10.0.1.x（PaaS への入口）"]
            end
        end
        subgraph ZONE["Private DNS Zone: privatelink.blob.core.windows.net"]
            R1["&lt;account&gt;  A 10.0.1.x ← Zone Group が自動登録"]
        end
        STG["Storage (blob)<br/>publicNetworkAccess = Disabled<br/>（公開エンドポイントは閉）"]
    end

    PC -- "curl https://&lt;account&gt;.blob.core.windows.net" --> VM
    VM -- "① 名前を問い合わせ" --> ZONE
    ZONE -- "② 10.0.1.x（PEのIP）を返す" --> VM
    VM -- "③ その IP へ接続" --> PE
    PE -- "Private Link" --> STG
    VNet -- "link-to-vnet" --- ZONE

    style RG stroke:#9c27b0,stroke-width:2px
    style VNet stroke:#1565c0,stroke-width:2px
    style SubVm stroke:#2e7d32,stroke-width:2px
    style SubPe stroke:#2e7d32,stroke-width:2px
    style ZONE stroke:#00838f,stroke-width:2px
    style STG stroke:#e65100,stroke-width:2px
```

## 2. プライベート IP で到達するシーケンス（test-private）

宛先は公開エンドポイントと**同じ FQDN**。VM はまず DNS に問い合わせ、返ってきた**プライベート IP**へ接続する。

```mermaid
sequenceDiagram
    participant PC as あなたの PC (az CLI)
    participant VM as vm (Run Command)
    participant DNS as Azure DNS 168.63.129.16<br/>(privatelink ゾーンを解決)
    participant PE as pe-blob 10.0.1.x
    participant STG as Storage(blob)

    PC->>VM: curl https://<account>.blob.core.windows.net
    VM->>DNS: ① <account>.blob.core.windows.net は？
    DNS-->>VM: ② 10.0.1.x（リンク済み privatelink ゾーンの A レコード）
    VM->>PE: ③ 10.0.1.x へ TLS 接続
    PE->>STG: ④ Private Link 経由でサービスへ
    STG-->>VM: ⑤ HTTP 応答（到達できた証）
    Note over PC,STG: URL は公開エンドポイントと同じ。向き先だけがプライベート IP
```

## 3. 同じ FQDN が「プライベート IP / 公開 IP」を行き来する（unlink / link）

`just unlink` で Private DNS Zone のリンクを外すと、同じ公開 FQDN が**公開 IP**に解決される。
ネットワーク機器は不変で、**変わったのは名前解決の向き先だけ**（Step7 と同じ切り分け）。

```mermaid
sequenceDiagram
    participant VM as vm
    participant DNS as Azure DNS

    Note over VM,DNS: リンクあり（just test-private）
    VM->>DNS: <account>.blob.core.windows.net は？
    DNS-->>VM: 10.0.1.x（Private Endpoint のプライベート IP）

    Note over VM,DNS: just unlink 実行後
    VM->>DNS: <account>.blob.core.windows.net は？
    DNS-->>VM: 公開 IP（公衆 DNS の答え。もう 10.0.1.x ではない）
    Note over VM,DNS: just link で再びプライベート IP に戻る
```

## 4. 「名前解決」と「公開アクセス」は独立した 2 つのスイッチ

`unlink/link`（名前の向き先）と `disable-public/enable-public`（公開エンドポイントの開閉）は別物。
両方を絞ると「公開は閉じ、プライベートだけ通す」閉域構成になる。

```mermaid
flowchart LR
    subgraph DNS["スイッチ① 名前解決（Private DNS Zone リンク）"]
        D1["link → 公開FQDN が 10.0.1.x（PE）に解決"]
        D2["unlink → 公開FQDN が 公開IP に解決"]
    end
    subgraph PUB["スイッチ② 公開アクセス（publicNetworkAccess）"]
        P1["Enabled → 公開エンドポイントが開く"]
        P2["Disabled → 公開エンドポイントを閉じる"]
    end
    GOAL["link × Disabled<br/>= 公開は閉じ、プライベート(PE)だけ通す（閉域）"]
    D1 --> GOAL
    P2 --> GOAL
```
