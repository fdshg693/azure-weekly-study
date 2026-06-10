# advanced/step2: ネットワーク構成図

## 全体構成（エッジで受ける → オリジンへ転送）

```mermaid
graph TD
    User((利用者 / 攻撃者))

    subgraph Edge["Azure Front Door (グローバル・エニーキャストのエッジ)"]
        EP["Endpoint: *.azurefd.net<br/>(最寄り PoP で受ける)"]
        WAFP["WAF Policy: wafEdgePolicy<br/>RateLimitRule (30 req / 1 min / client IP)<br/>mode = Detection / Prevention"]
        OG["Origin Group<br/>(ヘルスプローブで生存確認)"]
    end

    subgraph Azure["Azure Region (japaneast)"]
        LAW["Log Analytics: log-edge<br/>(WAF / アクセスログ)"]
        PIP["Public IP: pip-origin<br/>(DNS ラベル付き FQDN)"]

        subgraph VNet["VNet: vnet-edge (10.0.0.0/16)"]
            subgraph SubnetOrigin["Subnet: subnet-origin (10.0.1.0/24)"]
                VM["vm-origin<br/>IP: 10.0.1.4<br/>(Nginx: 全パス 200)"]
            end
            NSG["NSG: nsg-origin<br/>Allow 80 from AzureFrontDoor.Backend のみ<br/>(直アクセスは既定 Deny)"]
        end
    end

    User -- "HTTPS Request" --> EP
    EP --> WAFP
    WAFP -- "閾値以下は通す" --> OG
    OG -- "HTTP/80 で転送<br/>(送信元 = AzureFrontDoor.Backend)" --> PIP
    PIP --- VM
    NSG -. "Assigned to" .-> SubnetOrigin
    EP -. "診断ログ送信" .-> LAW

    User -. "直アクセス試行 (test-direct)<br/>NSG で遮断" .-x PIP

    style Edge stroke:#e65100,stroke-width:2px
    style Azure stroke:#9c27b0,stroke-width:2px
    style VNet stroke:#1565c0,stroke-width:2px
    style SubnetOrigin stroke:#2e7d32,stroke-width:2px
    style WAFP stroke:#c62828,stroke-width:2px
    style NSG stroke:#c62828,stroke-width:2px
    style PIP stroke:#00838f,stroke-width:2px
    style LAW stroke:#6a1b9a,stroke-width:2px
    style VM stroke:#2e7d32,stroke-width:2px
```

## 体積型攻撃の緩和（flood × mode の出し入れ）

短時間に大量のリクエストを送ったとき、WAF の mode によって結末が変わる。

```mermaid
graph TD
    BURST["短時間に大量リクエスト<br/>(同一クライアント IP)"]
    EDGE["Front Door エッジ<br/>クライアント IP ごとに計数"]
    RL{"レート制限: 30 req / 1 min を超過?"}

    BURST --> EDGE --> RL

    RL -->|"閾値以下"| PASS200["200 OK<br/>オリジンまで通す"]
    RL -->|"超過 & mode = Prevention"| BLOCK["429 Too Many Requests<br/>(エッジで弾く)"]
    RL -->|"超過 & mode = Detection"| PASS["200 OK<br/>(ブロックせずログだけ残す)"]

    style RL stroke:#c62828,stroke-width:2px
    style BLOCK stroke:#b71c1c,stroke-width:2px
    style PASS stroke:#2e7d32,stroke-width:2px
    style PASS200 stroke:#2e7d32,stroke-width:2px
```

## エッジ経由の強制（オリジンの lock / unlock）

オリジンへ「必ずエッジを通させる」のが NSG の service tag。出し入れで因果を確かめる。

```mermaid
graph LR
    subgraph LOCK["lock-origin (既定)"]
        U1((利用者)) -->|"エッジ経由 ✅ 200"| FD1["Front Door"] --> O1["origin"]
        A1((直アクセス)) -. "❌ NSG Deny" .-x O1
    end

    subgraph UNLOCK["unlock-origin (検証用に開放)"]
        U2((利用者)) -->|"エッジ経由 ✅ 200"| FD2["Front Door"] --> O2["origin"]
        A2((直アクセス)) -->|"⚠ 直接 200<br/>= エッジを迂回できてしまう"| O2
    end

    style LOCK stroke:#2e7d32,stroke-width:2px
    style UNLOCK stroke:#e65100,stroke-width:2px
```

## グローバル vs リージョン内（basic との対比）

```mermaid
graph LR
    subgraph R["basic/step9・10: リージョン内分散"]
        IN1((利用者)) --> LB["LB / App Gateway"] --> V1["VM 群 (同一リージョン)"]
    end

    subgraph G["advanced/step2: グローバル・エッジ"]
        IN2((利用者)) -->|"最寄り PoP"| AFD["Front Door (世界中のエッジ)"] --> V2["オリジン (リージョン)"]
    end

    style R stroke:#1565c0,stroke-width:2px
    style G stroke:#e65100,stroke-width:2px
```
