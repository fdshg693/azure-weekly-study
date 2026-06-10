# Step10: L7 リバースプロキシ／パスベースルーティング — Application Gateway

このステップでは、**Azure Application Gateway** を用いて、HTTP の **URL パス** に基づいて受信トラフィックを別々のバックエンドへ振り分ける構成を学びます。これは「候補C」として計画されていたものです。

Step9（候補B / Load Balancer）が **L4（IP・ポート）** で分散していたのに対し、本ステップは **L7（HTTP のパス・ホスト名）** で振り分けます。「何を見て振り分けているか」の差分を体感するのが狙いです。

## 学ぶ概念
- **L7（アプリケーション層）のルーティング**: L4 が「IP アドレス・ポート番号」しか見ないのに対し、L7 では HTTP リクエストの中身（**URL パス**やホスト名）を見て振り分け先を決めます。
- **リバースプロキシ**: クライアントは Application Gateway としか通信せず、Gateway が裏側のバックエンドへ代理でリクエストを中継します。クライアントから見るとバックエンドの構成は隠蔽されます。
- **パスベースルーティング**: `/api/*` は API サーバー群へ、それ以外（`/*`）は Web サーバー群へ、というように **URL のパスで宛先を切り替える**仕組みです。
- **TLS 終端（概念）**: L7 で中身を見られるということは、Gateway 上で HTTPS を復号（TLS 終端）し、検査・ルーティングできることを意味します（本ステップでは HTTP のみ構成し、概念として整理します）。

## L4（Step9）との対比

| 観点 | Step9: Load Balancer (L4) | Step10: Application Gateway (L7) |
| --- | --- | --- |
| 動作レイヤ | トランスポート層（TCP/UDP） | アプリケーション層（HTTP/HTTPS） |
| 振り分けの判断材料 | 5タプル（送信元/宛先 IP・ポート、プロトコル） | URL パス・ホスト名・ヘッダ等 |
| できること | 接続単位の分散 | パス/ホストで宛先を切替、TLS 終端、URL 書き換え等 |
| 専用サブネット | 不要 | **必要**（Application Gateway 専用サブネット） |

## 構成
- **VNet**: `vnet-appgw` (`10.0.0.0/16`)
- **Subnet**:
  - `subnet-appgw` (`10.0.1.0/24`): **Application Gateway 専用サブネット**（他のリソースと同居できません）
  - `subnet-backend` (`10.0.2.0/24`): バックエンド VM を配置
- **NSG**: `nsg-appgw`（Gateway Manager 用の `65200-65535` と HTTP `80` を許可）、`nsg-backend`（HTTP `80` を許可）
- **Public IP**: `pip-appgw` (Standard SKU / Static)
- **Application Gateway**: `appgw` (Standard_v2)
  - リスナー: HTTP ポート80
  - バックエンドプール: `web-pool`（`10.0.2.4`）, `api-pool`（`10.0.2.5`）
  - **URL パスマップ**: `/api/*` → `api-pool`、既定（それ以外）→ `web-pool`
- **VM**: `vm-web`（`10.0.2.4`）, `vm-api`（`10.0.2.5`）（Ubuntu 22.04）
  - Cloud-init (`customData`) で Nginx をインストールし、**どのパスへのアクセスでも自分の役割（WEB / API）を返す**ように設定しています。

## 手順

### 1. リソースのデプロイ

```bash
cd step10
just deploy
```
デプロイが完了すると、Application Gateway の Public IP が `appgw_ip.txt` に保存されます。
> **Note**: VM が起動した後、バックグラウンドで `apt-get install nginx` が走るため、バックエンドが応答を返し、Application Gateway のヘルス状態が正常になるまでに数分程度かかる場合があります。Application Gateway 自体のデプロイにも 5〜10 分ほどかかります。

### 2. パスベースルーティングの確認

デプロイ後、少し待ってから `just test` を実行します。

```bash
just test
```

`/`（既定）と `/web/` は **WEB バックエンド**へ、`/api/` は **API バックエンド**へ振り分けられることが確認できます。

```text
--- GET / ---
Response from WEB backend (vm-web)
--- GET /web/ ---
Response from WEB backend (vm-web)
--- GET /api/ ---
Response from API backend (vm-api)
```

同じ Public IP（同じ入口）に対するアクセスでも、**URL のパスだけで宛先が変わる**ことが L7 ルーティングの本質です。Step9 の L4 では、URL を変えても宛先は変わりませんでした。

### 3. バックエンドの健全性を確認（任意）

Application Gateway がバックエンドをどう見ているか（Healthy / Unhealthy）を確認できます。

```bash
just health
```

## クリーンアップ

検証が終わったらリソースグループごと削除します。

```bash
just cleanup
```
