# Step1 (advanced): L7 を「守る」 — WAF と TLS 終端

このステップは `advanced` の最初のステップで、`PLAN.md` の **案4** を実装したものです。
basic/step10（Application Gateway・L7 パスベースルーティング・TLS 終端の「概念」）の直接の発展として、
L7 リバースプロキシを「振り分ける場所」から「**通す前に中身を検査して防ぐ場所**」へ引き上げます。

## このステップで解く問題（まず一般概念）

L7 リバースプロキシは、HTTP の中身（URL・ヘッダ・ボディ）を読める位置にいます。だからこそ次の 2 つを一体で担えます。

1. **TLS 終端**：入口で HTTPS を復号する。復号して初めて中身を読めるので、検査やルーティングが成立する。証明書をどこに置き・どう運用するかがセットになる。
2. **WAF（Web Application Firewall）**：復号後の HTTP を、既知の攻撃パターン（SQLi / XSS など OWASP Top 10 系）と照合し、**検知（ログのみ）** または **防御（実ブロック）** する。

basic/step11（Azure Firewall の FQDN egress 制御）が「**外向き**の検査」だったのに対し、本ステップは「**内向き**の検査」です。

## Azure 実現

- **Application Gateway を `WAF_v2` SKU** で構成し、**WAF ポリシー**（OWASP 3.2 マネージドルールセット）を関連付ける。
- リスナーを **HTTPS(443)** にし、**自己署名証明書で TLS 終端**する（バックエンドへは HTTP(80) でオフロード）。
- WAF ポリシーの `mode` を **Detection ⇄ Prevention** で出し入れし、「ログだけ／実ブロック」の差を観測する。
- 診断設定で **WAF ログ** を Log Analytics に送り、検知の記録を後から確認する。

> 学習手法は basic と同じ ―― 「設定を出し入れして、通信の変化から因果を確かめる」。ここで出し入れするスイッチは **WAF の mode** です。

## ファイル構成（Bicep はモジュール分割）

構成が大きくなるため、1 つの巨大ファイルにせず役割ごとに分割しています。

```
step1/
├── main.bicep              … オーケストレータ（各モジュールを呼ぶだけ）
└── modules/
    ├── network.bicep       … VNet・2 サブネット・NSG・Public IP
    ├── backend.bicep       … バックエンド VM（Nginx。どのパスでも 200 を返す）
    ├── waf-policy.bicep     … WAF ポリシー（OWASP ルールセット・mode）
    ├── appgw.bicep         … Application Gateway(WAF_v2)・HTTPS リスナー・TLS 証明書・診断設定
    └── monitoring.bicep    … Log Analytics ワークスペース
```

## 構成

- **VNet**: `vnet-waf` (`10.0.0.0/16`)
  - `subnet-appgw` (`10.0.1.0/24`): **Application Gateway 専用サブネット**
  - `subnet-backend` (`10.0.2.0/24`): バックエンド VM
- **NSG**: `nsg-appgw`（Internet からの `443` と GatewayManager `65200-65535` を許可）、`nsg-backend`（VNet からの `80` を許可）
- **Public IP**: `pip-appgw`（Standard / Static）
- **Application Gateway**: `appgw-waf`（**WAF_v2**）
  - リスナー: **HTTPS / 443**（自己署名証明書で TLS 終端）
  - バックエンドプール: `backend-pool`（`10.0.2.4`、HTTP/80 へ転送）
  - **WAF ポリシー** `waf-policy`（OWASP 3.2）を関連付け
- **VM**: `vm-backend`（`10.0.2.4`、Ubuntu 22.04 / Nginx）。どのパスでも `200` を返すので、WAF を通過したかどうかが分かりやすい。
- **Log Analytics**: `log-waf`（WAF ログの確認用）

## 前提

- `az` CLI（ログイン済み）、`just`、`openssl`、`base64`（Git Bash 等に同梱）。
- 証明書は学習用の自己署名証明書を `just` が自動生成します（CN=`appgw.example.local`）。
  そのためブラウザ/`curl` では証明書検証エラーになるので、`curl -k`（検証スキップ）で確認します。

## 手順

### 1. デプロイ（証明書は自動生成）

```bash
cd advanced/step1
just deploy
```

`just deploy` は内部で `just cert`（自己署名 PFX 生成）→ Bicep デプロイ → Public IP/Workspace ID の保存を行います。
初期状態の WAF mode は **Prevention（実ブロック）** です。

> **Note**: Application Gateway WAF_v2 のデプロイには 5〜10 分、バックエンド Nginx の起動には数分かかります。

### 2. 正常リクエスト（TLS 終端の確認）

```bash
just test
```

HTTPS でアクセスし、バックエンドまで届いて `200` が返ること（= 入口で TLS 終端できていること）を確認します。

```text
--- normal request: GET / ---
Reached BACKEND (vm-backend) uri=/
HTTP 200
```

### 3. 悪性リクエスト × mode の出し入れ（このステップの核心）

まず **Prevention** のまま攻撃パターンを投げます。WAF が手前で弾くので `403` が返ります。

```bash
just attack
```
```text
--- GET /?id=1' OR '1'='1 ---
...403 が返る（バックエンドには届かない）...
HTTP 403
```

次に **Detection（ログのみ）** に切り替えて、同じ攻撃を投げます。

```bash
just mode-detection
just attack
```
```text
--- GET /?id=1' OR '1'='1 ---
Reached BACKEND (vm-backend) uri=/?id=1' OR '1'='1
HTTP 200
```

同じリクエストなのに、**mode を変えただけで `403`（実ブロック）⇄ `200`（バックエンドまで到達＝ログのみ）** と変わります。
これが「検知（Detection）」と「防御（Prevention）」の違いであり、止めているのが **WAF の mode** であることの切り分けです。
元に戻すには `just mode-prevention`。現在値は `just mode-show` で確認できます。

### 4. WAF ログの確認（任意）

Detection 時も「ログだけは残る」ことを確認します（Log Analytics への反映まで数分のラグがあります）。

```bash
just logs
```

`action_s`（Matched/Blocked）・`ruleId_s`（一致した OWASP ルール）・`requestUri_s` などが記録されています。

### 5. バックエンドの健全性（任意）

```bash
just health
```

## basic との対比

| 観点 | basic/step10 (App Gateway) | basic/step11 (Azure Firewall) | 本ステップ (WAF + TLS) |
| --- | --- | --- | --- |
| 主眼 | どこへ振り分けるか（L7 ルーティング） | 外向き(egress)の検査・制御 | **内向き(ingress)の検査・防御** |
| 見るもの | URL パス・ホスト名 | 宛先 FQDN | **HTTP の中身（攻撃パターン）** |
| TLS | 概念のみ（HTTP 構成） | ― | **実際に TLS 終端（HTTPS リスナー＋証明書）** |
| 出し入れスイッチ | パスマップ | `0.0.0.0/0` ルート | **WAF mode（Detection ⇄ Prevention）** |

## クリーンアップ

```bash
just cleanup
```

リソースグループの削除に加え、ローカルの証明書ファイル（`appgw-cert.*`）と一時ファイルも削除します。
