# Step 7: 名前で到達する — Private DNS Zone（名前解決）

Step1〜6 では、宛先をすべて **プライベート IP の直打ち**（例: `ping 10.0.1.5`）で指定してきました。
しかし IP は分かりにくく、台数が増えたり再作成で変わったりすると破綻します。
現実の運用では「**名前**」で到達したい——それを支えるのが **名前解決（DNS）** です。

このステップでは、VNet 内だけで通用する独自のゾーン **`corp.internal`** を **Private DNS Zone** で用意し、
`vm-b.corp.internal` のような **名前**で ping できることを確認します。
名前と IP の対応は 2 通りで持たせます。

* **自動登録（auto-registration）**：VM が起動時に自分のホスト名を自動でゾーンに登録する。
* **手動レコード**：人が分かりやすい別名（`app.corp.internal`）を手で登録する。

そして「**リンクを外すと名前は引けないが IP では届く**」ことを対比で確認し、
名前解決を担っているのが Private DNS Zone であることを切り分けます（Step1〜6 で使ってきた
「許可/経路を出し入れして因果を確かめる」のと同じ手法）。

## 目的
* IP 直打ちから **名前解決（DNS）** へ発想を移す：名前 → IP の対応表を持つ仕組みを理解する。
* **Private DNS Zone** を VNet に **リンク**して、VNet 内だけで通用する名前空間を作る。
* **自動登録**（リンクの `registrationEnabled = true`）と **手動レコード**の違いを体感する。
* **リンクの有無で名前解決だけが変わる**（IP 到達性は不変）ことを確認し、解決を担っているのが
  Private DNS Zone だと切り分ける。

## 前提条件
* [Azure CLI](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli)（`az login` 済み）
* [Just](https://github.com/casey/just)
* Step1〜2 の **VNet・サブネット・NSG・VM**、および VM 内からの疎通確認（Azure VM Run Command による ping）を理解していること。
  * 本ステップは外部からの SSH を使いません。検証はすべて **Run Command**（VM 上でコマンド実行）で行うため、SSH 鍵や公開 IP は不要です（Step2 と同じ方式）。

> このステップは、後続の **候補 E（Private Endpoint / Private Link）** の前提として効きます。
> 「サービス名をプライベート IP に解決させる」考え方が、ここで身につく名前解決の延長線上にあります。

## 構成されるリソース
`main.bicep` ファイルにより、以下のリソースがデプロイされます。
* **リソースグループ**: `rg-network-learn-privatedns`（東日本リージョン）
* **VNet**: `vnet-privatedns` (10.0.0.0/16) / サブネット `subnet-main` (10.0.1.0/24)
  * **vm-a**: プライベート IP **10.0.1.4**（静的）。公開 IP なし。
  * **vm-b**: プライベート IP **10.0.1.5**（静的）。公開 IP なし。
  * NSG `nsg-main`: VNet 内からの **ICMP / SSH** を許可（名前で引いても IP で引いても、届く先は同じ VM）。
* **Private DNS Zone**: `corp.internal`（グローバルリソース。インターネットには非公開）
  * **VNet リンク** `link-to-vnet`（`registrationEnabled: true` = 自動登録 ON）
  * **手動レコード** `app.corp.internal` → `10.0.1.5`（vm-b への別名）
* デプロイ後、VM の起動に伴って **`vm-a` / `vm-b` の A レコードがゾーンに自動登録**されます。

### 構成イメージ
```
   [あなたのPC] --az vm run-command--> vm-a 上でコマンド実行
                                          │ ping vm-b.corp.internal
   ┌──────────── vnet-privatedns (10.0.0.0/16) ───────────┐
   │  subnet-main (10.0.1.0/24)                            │
   │     vm-a 10.0.1.4        vm-b 10.0.1.5                │
   └───────────────────────────┬──────────────────────────┘
                                │ リンク (registration = ON)
                                ▼
   ┌──────── Private DNS Zone: corp.internal（VNet 内だけで有効）────────┐
   │  vm-a  A 10.0.1.4   ← 自動登録    app  A 10.0.1.5   ← 手動レコード    │
   │  vm-b  A 10.0.1.5   ← 自動登録                                      │
   └────────────────────────────────────────────────────────────────────┘
```
> 名前解決はこの「リンク」があって初めて効きます。リンクを外すと、VM はこのゾーンを引けなくなります。

---

## 実行手順

コマンドはすべてこの `step7` ディレクトリで実行してください。

### 1. リソースのデプロイ
```bash
just deploy
```
> デプロイ後、VM が起動して自動登録が反映されるまで **1〜2 分**ほど待つと確実です。

### 2. ゾーンとリンク・レコードの確認
ゾーン、VNet リンク（自動登録の有無）、そして自動登録された `vm-a` / `vm-b` と手動の `app` を確認します。
```bash
just info          # ゾーンとリンク（registrationEnabled = 自動登録）
just show-records  # vm-a / vm-b（自動登録）と app（手動）が並ぶ
```

### 3. 名前で到達する（成功テスト）
vm-a 上から、**IP を一切打たずに** vm-b へ名前で到達します。
```bash
just test-dns
```
> `vm-b.corp.internal` が `10.0.1.5` に解決され ping が通る／`app.corp.internal` も同じ IP に解決される、
> ことが確認できれば成功です。Step1〜6 の「IP 直打ち」が「名前」に置き換わりました。

### 4. 手動レコードを足してみる（任意）
別名を**手で**1 件追加し、もう一方の VM から解決します（bicep の `app` と同じ操作を対話的に体験）。
```bash
just add-alias     # db.corp.internal -> 10.0.1.4(vm-a) を追加し、vm-b から解決
```

### 5. リンクを外すと「名前は引けないが IP では届く」（切り分けテスト）
VNet とゾーンのリンクを削除します。
```bash
just unlink
just test-dns      # → 名前解決に FAIL する（vm-b.corp.internal が引けない）
just test-ip       # → 同じ宛先に IP(10.0.1.5) では SUCCESS する
```
→ ネットワークの経路は変わっておらず、**変わったのは名前解決だけ**。
   名前で届いていたのは Private DNS Zone（とそのリンク）のおかげだと切り分けられます
   （Step1〜6 の NSG/UDR/NAT GW の出し入れと同じ考え方）。

### 6. リンクを戻して再び名前で届くようにする
```bash
just link
just test-dns      # app.corp.internal は即座に解決。vm-a/vm-b の自動登録は数分で再反映
```
> 手動レコード（`app`）はゾーンに残っているのでリンク復活と同時に引けます。
> 自動登録（`vm-a`/`vm-b`）は VM の再登録に少し時間がかかる場合があります。

### 7. リソースの削除（クリーンアップ）
```bash
just destroy
```

---

## このステップの要点
* **名前解決（DNS）** は「名前 → IP の対応表」を引く仕組み。IP 直打ちの脆さ（変わる・覚えにくい）を解消する。
* **Private DNS Zone** は VNet 内だけで通用する独自の名前空間。インターネットの DNS には公開されない。
* 名前と IP の対応は **自動登録**（VM のホスト名が起動時に登録される）と **手動レコード**（人が付ける別名）の 2 通り。
* 名前解決は **VNet とゾーンのリンク**があって初めて効く。リンクを外すと「**名前は引けないが IP では届く**」
  状態になり、解決を担っているのが Private DNS Zone だと切り分けられる。
* この名前解決の考え方は、**候補 E（Private Endpoint / Private Link）** で「サービス名をプライベート IP に向ける」
  際の前提になる。
