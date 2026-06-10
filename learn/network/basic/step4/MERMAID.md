# Step 4 構成図（Mermaid）

踏み台（bastion）越しのプライベート VM アクセスを表現します。

## 1. リソース構成図

1 つの VNet を「公開ゾーン（踏み台）」と「非公開ゾーン（private VM）」の 2 サブネットに分ける。
インターネットに開くのは**踏み台だけ**で、しかも SSH 元は自分の IP に限定する。

```mermaid
flowchart TD
    PC["あなたの PC<br/>(秘密鍵 bastion_key を保持)"]

    subgraph RG["リソースグループ rg-network-learn-bastion"]
        NSGB["nsg-bastion<br/>SSH 許可: 自分の IP /32 のみ"]
        NSGP["nsg-private<br/>SSH 許可: 10.0.0.0/24 のみ"]
        subgraph VNet["vnet-bastion (10.0.0.0/16)"]
            subgraph SubB["subnet-bastion (10.0.0.0/24) = 公開ゾーン"]
                BAS["vm-bastion 10.0.0.4<br/>public IP あり（唯一の入口）"]
            end
            subgraph SubP["subnet-private (10.0.1.0/24) = 非公開ゾーン"]
                PRIV["vm-private 10.0.1.x<br/>public IP なし"]
            end
        end
    end

    PC -- "SSH(22) 自分の IP からのみ許可" --> BAS
    BAS -- "内部 SSH（送信元=踏み台サブネット）" --> PRIV
    NSGB -. 適用 .-> SubB
    NSGP -. 適用 .-> SubP

    style RG stroke:#9c27b0,stroke-width:2px
    style VNet stroke:#1565c0,stroke-width:2px
    style SubB stroke:#e65100,stroke-width:2px
    style SubP stroke:#2e7d32,stroke-width:2px
```

## 2. 多段 SSH（ProxyJump）の流れ — 秘密鍵はローカルから出ない

`ssh -J azureuser@<踏み台> azureuser@<private>` の 1 コマンドで貫通する。
踏み台は「最終ホストへの TCP 接続を中継するだけ」で、SSH 認証は PC↔private で直接行う。

```mermaid
flowchart LR
    PC["ローカル PC<br/>秘密鍵あり"]
    NSGB{"nsg-bastion<br/>src = 自分の IP ?"}
    BAS["vm-bastion 10.0.0.4<br/>接続を中継するだけ<br/>（鍵は置かない）"]
    NSGP{"nsg-private<br/>src = 10.0.0.0/24 ?"}
    PRIV["vm-private 10.0.1.x<br/>public IP なし"]

    PC --> NSGB -- 許可 --> BAS
    BAS -- "private:22 への TCP を中継" --> NSGP
    NSGP -- "src は踏み台の IP" --> PRIV
    PRIV -. "認証は PC↔private で直接（エンドツーエンド）<br/>秘密鍵は PC から出ない" .-> PC
```

## 3. シナリオ: 直接は入れない / 踏み台経由なら入れる

private VM はパブリック IP を持たないため、ローカルから直接 SSH すると届かない。
踏み台を経由すると到達できる。

```mermaid
sequenceDiagram
    participant PC as ローカル PC
    participant B as vm-bastion (public IP)
    participant P as vm-private (public IP なし)

    Note over PC,P: シナリオ A: 直接 SSH（just test-direct-fail）
    PC--xP: private IP へ直接 SSH
    Note over P: インターネットから届く入口が無い → タイムアウト

    Note over PC,P: シナリオ B: 踏み台経由（just test-jump）
    PC->>B: ① SSH（自分の IP からのみ許可）
    B->>P: ② private:22 への接続を中継（src=踏み台サブネット → nsg-private 許可）
    P-->>PC: ③ 公開鍵認証成立 → ログイン成功
```

## 4. シナリオ: NSG の許可を出し入れすると通信が変わる

`just lock-private` / `unlock-private` で、private VM に入れていたのが
**nsg-private の踏み台サブネット許可**だと確認できる。

```mermaid
sequenceDiagram
    participant PC as ローカル PC
    participant B as vm-bastion
    participant N as nsg-private
    participant P as vm-private

    Note over PC,P: 許可あり（just test-jump 成功）
    PC->>B: ssh -J で踏み台へ
    B->>N: private:22 へ（src 10.0.0.0/24）
    N->>P: Allow-SSH-From-Bastion に一致 → 許可
    P-->>PC: ログイン成功

    Note over PC,P: just lock-private 実行後
    PC->>B: ssh -J で踏み台へ
    B->>N: private:22 へ（src 10.0.0.0/24）
    N--xB: 許可ルールが無い → 拒否
    Note over PC: ジャンプ失敗（入れていたのは NSG の許可があったから）
```

## 5. 踏み台（L7 で接続を張り直す）と NVA（L3 で素通し転送）の違い

Step3 の NVA はパケットを転送するだけ（NAT しない＝送信元は元のまま）。
踏み台は SSH 接続を張り直す（private から見た送信元は踏み台になる）。

```mermaid
flowchart TD
    subgraph NVA["Step3: NVA（中継ルーター / L3）"]
        A1["spoke1 10.1.0.4"] --> A2["NVA がフォワード<br/>送信元を書き換えない"] --> A3["spoke2 から見た src = 10.1.0.4（元のまま）"]
    end
    subgraph BAS["Step4: 踏み台（jump box / L7）"]
        B1["PC"] --> B2["踏み台で SSH を張り直す"] --> B3["private から見た src = 踏み台の IP（10.0.0.x）"]
    end
```
