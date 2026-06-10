# Step2 (advanced): 可用性とエッジ防御 — Front Door / DDoS Protection

このステップは `PLAN.md` の **案5** を実装したものです。
basic/step9・10（リージョン内の負荷分散）と advanced/step1（リージョン内の WAF）の発展として、
受け口を **リージョン内** から **グローバルなエッジ（ユーザーに近い場所）** へ引き上げ、
そこで **体積型攻撃を緩和** し、**オリジンへの直アクセスを塞ぐ**「入口の作り込み」を学びます。

## このステップで解く問題（まず一般概念）

公開エンドポイントは攻撃（特に体積型 DDoS／フラッディング）の標的になります。守りの定石は次の 3 点です。

1. **エッジで受ける**：利用者に近い PoP でまず受け止める。近い＝速い、そして**攻撃もまずエッジが受けてオリジンを守る**。
2. **体積型を緩和する**：エッジで「1 クライアントあたりのリクエスト数」を見て、異常な連打を **レート制限**で弾く。
3. **迂回させない**：オリジンに直接到達させず、**必ずエッジを通させる**（エッジ・フロンティング）。

basic/step9・10 が「**リージョン内**でどう振り分けるか」だったのに対し、本ステップは「**世界中のエッジ**でどう受けて守るか」です。

## Azure 実現

- **Azure Front Door（Standard）** をグローバルな L7 エッジ入口として置く。エンドポイント（`*.azurefd.net`）はエニーキャストで公開される。
- Front Door の **WAF ポリシー**に **レート制限ルール（30 req / 1 分 / クライアント IP）** を 1 本だけ載せ、体積型の緩和を体感する。
- WAF ポリシーの `mode` を **Detection ⇄ Prevention** で出し入れし、「ログだけ／実 429 ブロック」の差を観測する（step1 と同じスイッチ）。
- オリジン（Nginx VM）の **NSG で送信元を `AzureFrontDoor.Backend` だけに限定**し、直アクセスを塞ぐ。`lock`/`unlock` で出し入れする。
- **DDoS Protection（有償プラン）は概念のみ**で、デプロイしません（高額なため）。L3/L4 の体積型は「Azure 基盤の常時 DDoS 防御が働く」という整理に留めます（詳細は `KNOWLEDGE.md`）。

> 学習手法は basic と同じ ―― 「設定を出し入れして、通信の変化から因果を確かめる」。
> ここで出し入れするスイッチは **WAF の mode** と **オリジンの直アクセス lock/unlock** の 2 つです。

## ファイル構成（Bicep はモジュール分割）

```
step2/
├── main.bicep              … オーケストレータ（各モジュールを呼ぶだけ）
└── modules/
    ├── network.bicep       … VNet・サブネット・NSG(Front Door だけ許可)・DNS ラベル付き Public IP
    ├── origin.bicep        … オリジン VM（Nginx。どのパスでも 200 を返す）
    ├── waf-policy.bicep     … Front Door WAF ポリシー（レート制限・mode）
    ├── frontdoor.bicep     … Front Door 本体（エンドポイント・オリジン・ルート・WAF 適用・診断設定）
    └── monitoring.bicep    … Log Analytics ワークスペース
```

## 構成

- **Front Door**: `afd-edge`（**Standard_AzureFrontDoor**）
  - エンドポイント: `edge-endpoint-xxxx.z01.azurefd.net`（エニーキャスト）
  - オリジン: オリジン VM の公開 FQDN へ HTTP/80 で転送
  - **WAF ポリシー** `wafEdgePolicy`（レート制限：30 req / 1 min / client IP）を適用
- **VNet**: `vnet-edge` (`10.0.0.0/16`)
  - `subnet-origin` (`10.0.1.0/24`): オリジン VM
- **NSG**: `nsg-origin`（HTTP/80 を **`AzureFrontDoor.Backend` からのみ**許可。直アクセスは既定 Deny）
- **Public IP**: `pip-origin`（Standard / Static / DNS ラベル付き）
- **VM**: `vm-origin`（`10.0.1.4`、Ubuntu 22.04 / Nginx）。どのパスでも `200` を返し、`uri` と `X-Forwarded-For` を表示する。
- **Log Analytics**: `log-edge`（WAF ログの確認用）

## 前提

- `az` CLI（ログイン済み）、`just`。
- Front Door の CLI（`az network front-door waf-policy ...`）には拡張機能が要るため、`just` が `az extension add -n front-door` を自動で行います。
- Front Door のエンドポイントは **HTTPS（Microsoft 管理証明書）** で待ち受けるので、`curl` の `-k` は不要です。

## 手順

### 1. デプロイ

```bash
cd advanced/step2
just deploy
```

デプロイ後、Front Door のエンドポイント名は `afd_host.txt`、オリジンの公開 IP は `origin_ip.txt` に保存されます。
初期状態の WAF mode は **Prevention（実ブロック）** です。

> **Note**: Front Door のエッジ伝播に数分、オリジン Nginx の起動・ヘルスプローブ成立にも数分かかります。最初の `just test` が 502/504 を返す場合は少し待って再実行してください。

### 2. エッジ経由で届くことの確認（正常リクエスト）

```bash
just test
```

```text
Testing via edge: https://edge-endpoint-xxxx.z01.azurefd.net/
Reached ORIGIN (vm-origin) uri=/ xff=<利用者のIP>
HTTP 200
```

エッジ（Front Door）で受けてオリジンまで届いていること、オリジンから見た送信元が `X-Forwarded-For` に入っていることが分かります。

### 3. オリジンへの直アクセスは塞がっていることの確認（エッジ・フロンティング）

```bash
just test-direct
```

オリジンの公開 IP へ直接アクセスすると、NSG が `AzureFrontDoor.Backend` 以外を拒否するためタイムアウト/失敗します（= 必ずエッジを通る構図）。

`unlock`/`lock` で因果を切り分けます。

```bash
just unlock-origin   # NSG に Allow-Direct-Internet を足す
just test-direct     # → 直接 200 が返る（エッジを迂回できてしまう）
just lock-origin     # ルールを外す
just test-direct     # → 再び遮断される
```

塞いでいたのが **NSG の service tag 制限** であることが切り分けられます。

### 4. 体積型攻撃の緩和 × mode の出し入れ（このステップの核心）

まず **Prevention** のまま、短時間に大量のリクエストを送ります。閾値（30/分）を超えた分が `429` で弾かれます。

```bash
just flood 60
```
```text
Sending 60 requests to https://.../ ...
200 OK: 30 / 429 Too Many Requests: 30 / other: 0
```

次に **Detection（ログのみ）** に切り替えて、同じバーストを送ります。

```bash
just mode-detection
just flood 60
```
```text
200 OK: 60 / 429 Too Many Requests: 0 / other: 0
```

同じ連打でも、**mode を変えただけで `429`（実ブロック）⇄ `200`（全て通過＝ログのみ）** に変わります。
これがエッジでの「体積型攻撃の緩和」であり、止めているのが **WAF の mode** であることの切り分けです。
元に戻すには `just mode-prevention`。現在値は `just mode-show`。

> 200/429 の内訳は厳密に閾値どおりにはなりません（レート制限は **PoP 単位**で計数され、1 分の窓でカウンタがリセットされるため）。「429 が出る／出ない」の差が見えれば十分です。窓を空けたいときは 1 分ほど待ってから再実行します。

### 5. WAF ログの確認（任意）

Detection 時も「ログだけは残る」ことを確認します（Log Analytics への反映まで数分のラグがあります）。

```bash
just logs
```

`action_s`（Block/Log）・`ruleName_s`（`RateLimitPerClientIp`）・`clientIP_s`・`requestUri_s` などが記録されています。

## basic / step1 との対比

| 観点 | basic/step9・10 | advanced/step1 (App Gateway WAF) | 本ステップ (Front Door) |
| --- | --- | --- | --- |
| 受け口 | リージョン内の LB / App Gateway | リージョン内の App Gateway | **グローバル・エッジ（エニーキャスト）** |
| 主眼 | どこへ振り分けるか | HTTP の中身を検査（SQLi/XSS） | **エッジで受けて体積型を緩和** |
| WAF ルール | ― | OWASP マネージドルールセット | **レート制限（カスタムルール）** |
| 出し入れスイッチ | プール/パスマップ | WAF mode | **WAF mode ＋ オリジンの lock/unlock** |

> Front Door（エッジ）→ App Gateway（リージョン WAF）→ バックエンド と重ねれば「多層の入口防御」になります（案4＋案5）。

## クリーンアップ

```bash
just cleanup
```

リソースグループの削除に加え、ローカルの一時ファイル（`afd_host.txt`・`origin_ip.txt`・`workspace_id.txt`）を削除します。
