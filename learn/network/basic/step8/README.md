# Step 8: PaaS へプライベート接続 — Private Endpoint / Private Link

Step1〜7 で扱ってきたのは、**自分で建てた VM 同士**の通信でした。
しかし現実には、ストレージやデータベースのような **マネージドサービス（PaaS）** にも通信します。
それらは既定で、**公衆インターネット上の公開エンドポイント**（例: `<account>.blob.core.windows.net`）を持ちます。

このステップでは、その PaaS（Storage）へ **インターネットを経由せず、VNet 内のプライベート IP で** 到達する構成を学びます。
鍵になるのは 2 つの仕組みです。

* **Private Endpoint**：PaaS への入口となる **NIC を自分のサブネットに 1 枚生やす**。
  その NIC が VNet 内のプライベート IP（`10.0.1.x`）を持ち、そこが blob への入口になる。
* **Private DNS Zone（`privatelink.blob.core.windows.net`）**：公開エンドポイントと**同じ FQDN** を、
  その**プライベート IP に解決**させる。アプリは URL を一切変えずに、名前解決の向き先だけが
  「公開 IP → プライベート IP」に変わる。

これは Step7 で学んだ「**名前 → IP の対応表**」の延長線上にあります。違いは “向き先がプライベート IP” という点だけ。
さらに、サービス側の **公開アクセスを無効化**（`publicNetworkAccess: Disabled`）して、
「**公衆インターネットの入口を閉じ、プライベート経路だけを開ける**」を成立させます。

## 目的
* PaaS（マネージドサービス）への通信が、既定では**公開エンドポイント（インターネット経由）**であることを理解する。
* **Private Endpoint** が「自分のサブネットに生える NIC」であり、PaaS への**プライベート IP の入口**になることを体感する。
* **同じ公開 FQDN** が、**Private DNS Zone のリンク有無**で「プライベート IP / 公開 IP」を行き来することを確認する
  （Step7 の名前解決の切り分けと同じ手法）。
* 「**公開を閉じる**（`publicNetworkAccess`）」と「**プライベートで開ける**（Private Endpoint）」が**別の操作**だと切り分ける。

## 前提条件
* [Azure CLI](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli)（`az login` 済み）
* [Just](https://github.com/casey/just)
* **Step7（Private DNS Zone による名前解決）** の理解。本ステップは「公開 FQDN をプライベート IP に解決させる」ので、
  名前解決の考え方（名前 → IP の対応表、VNet リンクの有無で解決が変わる）が前提になります。
* 検証はすべて **Run Command**（VM 上でコマンド実行）で行うため、SSH 鍵や公開 IP は不要です（Step2/Step7 と同じ方式）。

## 構成されるリソース
`main.bicep` ファイルにより、以下のリソースがデプロイされます。
* **リソースグループ**: `rg-network-learn-privatelink`（東日本リージョン）
* **VNet**: `vnet-privatelink` (10.0.0.0/16)
  * サブネット `snet-pe` (10.0.1.0/24)：**Private Endpoint** の NIC を置く（PaaS への入口）
  * サブネット `snet-vm` (10.0.2.0/24)：PaaS へアクセスする **vm**（プライベート IP **10.0.2.4**、公開 IP なし）
* **Storage Account**: `stpl<一意の文字列>`（**`publicNetworkAccess: Disabled`** = 公開エンドポイントは最初から閉じる）
* **Private Endpoint**: `pe-blob`（`groupIds: ['blob']`）。`snet-pe` 内にプライベート IP（`10.0.1.x`）を持つ NIC が生える。
* **Private DNS Zone**: `privatelink.blob.core.windows.net`（グローバルリソース）
  * **VNet リンク** `link-to-vnet`
  * **Private DNS Zone Group**：PE のプライベート IP を、このゾーンに **A レコードとして自動登録**する糊。

### 構成イメージ
```
   [あなたのPC] --az vm run-command--> vm 上でコマンド実行
                                          │ curl https://<account>.blob.core.windows.net
   ┌──────────── vnet-privatelink (10.0.0.0/16) ───────────────┐
   │  snet-vm (10.0.2.0/24)        snet-pe (10.0.1.0/24)        │
   │     vm 10.0.2.4  ───────────▶  pe-blob NIC 10.0.1.x ───┐   │
   └───────────────────────────────────────────────────────┼───┘
                                │ 名前解決                   │ Private Link
                                ▼                            ▼
   ┌─ Private DNS Zone: privatelink.blob.core.windows.net ─┐  ┌─ Storage(blob) ─┐
   │  <account>  A 10.0.1.x  ← Zone Group が自動登録        │  │ publicNetworkAccess
   └───────────────────────────────────────────────────────┘  │   = Disabled     │
                                                               └──────────────────┘
   公開 FQDN <account>.blob.core.windows.net は、リンク済み VNet 内では 10.0.1.x（PE）に解決される。
```
> 公開エンドポイントと**同じ URL** のまま、名前解決の向き先だけが「公開 IP → プライベート IP（PE）」に変わります。

---

## 実行手順

コマンドはすべてこの `step8` ディレクトリで実行してください。

### 1. リソースのデプロイ
```bash
just deploy
```
> Private Endpoint と DNS Zone Group の反映に少し時間がかかる場合があります。デプロイ完了後 **1〜2 分**待つと確実です。

### 2. ストレージ・PE・リンクの確認
```bash
just info          # storage の publicAccess（Disabled）、pe-blob の接続状態、DNS リンク
just show-records  # privatelink ゾーンに PE のプライベート IP が A レコードとして自動登録されている
```

### 3. プライベート IP で PaaS に到達する（成功テスト）
vm 上から、公開エンドポイントと**同じ FQDN** を解決し、接続します。
```bash
just test-private
```
> `getent hosts` の結果が **`10.0.1.x`（プライベート IP）** になっていれば成功です。
> 公開 IP ではなく Private Endpoint に解決されており、`curl` も HTTP コードを返します
> （= TLS/TCP がサービスに到達できている。認証していないので 400/403 などになるが「到達できた」ことの証）。

### 4. 名前解決を外すと「公開 IP に戻る」（切り分けテスト①：名前解決）
Private DNS Zone と VNet のリンクを削除します。
```bash
just unlink
just test-private   # → getent の結果が PUBLIC IP に変わる（もう 10.0.1.x ではない）
```
→ ネットワーク機器は何も変えていません。**変わったのは名前解決の向き先だけ**。
   公開 FQDN をプライベート IP に向けていたのが Private DNS Zone（とそのリンク）だと切り分けられます
   （Step7 の `unlink`/`link` と同じ考え方）。

```bash
just link
just test-private   # → 再び 10.0.1.x（Private Endpoint）に解決される
```

### 5. 公開エンドポイントを開け閉めする（切り分けテスト②：公開アクセス）
「名前解決」とは独立した、**サービス側の公開アクセス**のスイッチを出し入れします。
```bash
just enable-public    # 公開エンドポイントを開く（公開 IP 側からも到達可能に）
just disable-public   # 公開エンドポイントを閉じる（プライベート経路だけ残る）
```
→ `disable-public` の状態でも、**Private Endpoint 経由（プライベート IP）の到達性は変わりません**。
   「公開を閉じる」と「プライベートで開ける」は別の操作だと体感できます。
   （`unlink`（公開 IP に解決）× `disable-public`（公開を閉じる）を重ねると、
   公開 FQDN を引いても公開の扉は閉じている、という “閉域化” の効果が見えます。）

### 6. リソースの削除（クリーンアップ）
```bash
just destroy
```

---

## このステップの要点
* PaaS（マネージドサービス）への通信は、既定では**公衆インターネット上の公開エンドポイント**経由。
* **Private Endpoint** は「**自分のサブネットに生える NIC**」。PaaS への**プライベート IP の入口**になる。
* **Private DNS Zone（`privatelink.…`）** が、公開エンドポイントと**同じ FQDN** を**プライベート IP に解決**させる。
  アプリは URL を変えずに済む（Step7 の「名前 → IP」の延長。向き先がプライベート IP になっただけ）。
* **Private DNS Zone Group** が、PE のプライベート IP をゾーンへ**自動登録**する（手で A レコードを書かなくてよい）。
* **名前解決（`unlink`/`link`）** と **公開アクセス（`disable-public`/`enable-public`）** は**独立**。
  片方を出し入れしても、もう片方の効果はそのまま——この切り分けが「閉域でプライベートに繋ぐ」設計の勘所。
