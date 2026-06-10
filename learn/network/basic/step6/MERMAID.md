# Step 6 構成図（Mermaid）

自前の踏み台 VM（Step4）を、マネージドな **Azure Bastion** に置き換えて
パブリック IP を持たない private VM へ入る構成を表現します。

## 1. リソース構成図

踏み台 VM は存在せず、`AzureBastionSubnet` に置いた **Azure Bastion** が中継する。
利用者は生の SSH ポートではなく、Azure の認証済みセッション（CLI／ポータル）経由で到達する。

```mermaid
flowchart TD
    PC["あなたの PC<br/>az network bastion ssh / tunnel"]

    subgraph RG["リソースグループ rg-network-learn-azbastion"]
        NSGP["nsg-private<br/>inbound: 10.0.0.0/26 のみ<br/>(= AzureBastionSubnet)"]
        subgraph VNet["vnet-azbastion (10.0.0.0/16)"]
            subgraph SubB["AzureBastionSubnet (10.0.0.0/26)<br/>※予約名・/26 以上・VM は置かない"]
                BAS["Azure Bastion azbastion<br/>+ pip-azbastion (Standard)<br/>マネージドな踏み台（VM ではない）"]
            end
            subgraph SubP["subnet-private (10.0.1.0/24) = 非公開ゾーン"]
                PRIV["vm-private 10.0.1.x<br/>public IP なし"]
            end
        end
    end

    PC -- "認証済み Azure セッション" --> BAS
    BAS -- "VNet 内から SSH(22) で中継" --> PRIV
    NSGP -. 適用 .-> SubP

    style RG stroke:#9c27b0,stroke-width:2px
    style VNet stroke:#1565c0,stroke-width:2px
    style SubB stroke:#00838f,stroke-width:2px
    style SubP stroke:#2e7d32,stroke-width:2px
    style BAS stroke:#00838f,stroke-width:2px
```

## 2. Step4（自前踏み台）→ Step6（Azure Bastion）の差分

ゴール（public IP の無い VM へ入る）は同じ。**踏み台の実体と到達方法**が変わる。

```mermaid
flowchart LR
    subgraph S4["Step4: 自前踏み台 ＋ ssh -J"]
        direction TB
        P4["あなたの PC"] -- "SSH(22)<br/>自分の IP のみ許可" --> B4["vm-bastion<br/>public IP あり（自前 VM）"]
        B4 -- "ssh -J で中継" --> V4["vm-private<br/>public IP なし"]
    end
    subgraph S6["Step6: Azure Bastion（マネージド）"]
        direction TB
        P6["あなたの PC"] -- "認証済み Azure セッション<br/>(生の 22 番は無い)" --> B6["Azure Bastion<br/>（VM ではない）"]
        B6 -- "VNet 内から中継" --> V6["vm-private<br/>public IP なし"]
    end
```

## 3. 接続シーケンス — Azure Bastion 越しの SSH

`az network bastion ssh`（または tunnel）は、接続先を **VM のリソース ID** で指定する。
Bastion が VNet 内から対象のプライベート IP:22 へ中継する。

```mermaid
sequenceDiagram
    participant PC as あなたの PC (az CLI)
    participant AZ as Azure コントロールプレーン
    participant BAS as Azure Bastion (AzureBastionSubnet)
    participant VM as vm-private 10.0.1.x (public IP なし)

    PC->>AZ: ① az network bastion ssh（VM のリソース ID を指定／RBAC 認証）
    AZ->>BAS: ② 認証済みセッションを Bastion へ確立
    BAS->>VM: ③ VNet 内から SSH(22)（送信元 = AzureBastionSubnet）
    Note over VM: nsg-private が 10.0.0.0/26 からの SSH を許可
    VM-->>PC: ④ シェル（Bastion がトンネルで中継）
    Note over PC,VM: 生の 22 番をインターネットに開かず、踏み台 VM も無しで到達
```

## 4. シナリオ: NSG を出し入れすると Bastion 経由でも結果が変わる

`just lock-private` / `unlock-private` で、最終的に通しているのは
**private VM の NSG 許可（送信元 = AzureBastionSubnet）** だと確認する（Step4 と同じ手法）。

```mermaid
sequenceDiagram
    participant BAS as Azure Bastion
    participant NSG as nsg-private
    participant VM as vm-private

    Note over BAS,VM: 許可ルールあり（just connect 成功）
    BAS->>NSG: SSH(22)（src = AzureBastionSubnet）
    NSG->>VM: 許可 → 到達
    VM-->>BAS: シェル

    Note over BAS,VM: just lock-private 実行後
    BAS->>NSG: SSH(22)（src = AzureBastionSubnet）
    NSG--xBAS: Allow-SSH-From-Bastion が無い → 拒否（接続失敗）
    Note over BAS,VM: 踏み台がマネージドでも、許可を握るのは NSG
```

## 5. Step4 / Step6 の役割対比（踏み台の "誰が管理するか"）

```mermaid
flowchart TD
    subgraph BAS4["Step4: 自前踏み台 VM"]
        A["OS パッチ・sshd 設定・鍵管理を自分で持つ<br/>22 番をインターネット（自分の IP）に開く<br/>停止すれば安いが攻撃面が残る"]
    end
    subgraph BAS6["Step6: Azure Bastion（マネージド）"]
        B["中継基盤の運用は Azure が持つ<br/>生の 22 番は公開しない（認証済みセッション）<br/>時間課金・専用サブネット名などの制約"]
    end
```
