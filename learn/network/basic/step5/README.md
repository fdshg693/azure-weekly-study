# Step 5: パブリック IP を持たない VM の外向き通信（egress / SNAT）— NAT Gateway

Step4 では「受信を踏み台だけに絞った private VM（パブリック IP なし）」を作りました。
このステップはその自然な続きで、**その private VM が "外へ出る"（egress）通信をどう成立させるか**を学びます。

パブリック IP を持たないホストでも、OS 更新やパッケージ取得などで外へ出る必要はあります。
**受信は閉じたまま、送信だけを 1 つの出口（SNAT）に集約する**のが NAT Gateway です。
「inbound を閉じる」ことと「outbound を許す」ことは別物である、というのを手で動かして体感します。

## 目的
* **egress（外向き通信）と SNAT** の考え方を理解する：パブリック IP が無くても、出口さえあれば外へは出られる。出口は 1 つのパブリック IP に集約され、外から見た送信元 IP はその出口の IP になる。
* **「inbound を閉じる」と「outbound を許す」は別レイヤ**だと体感する：private VM は受信の入口を持たない（パブリック IP なし／NSG で踏み台だけ許可）が、送信の出口（NAT Gateway）は持てる。
* **NAT Gateway** をサブネットに関連付け、private VM から `curl`／`apt-get update` などが通ることを確認する。
* NAT Gateway を**外した状態と対比**し、egress を成立させているのが NAT Gateway であることを検証する（`defaultOutboundAccess: false` により、外すと確実に出られなくなる）。

## 前提条件
* [Azure CLI](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli) (事前に `az login` でログイン済みであること)
* [Just](https://github.com/casey/just)
* **OpenSSH クライアント**（`ssh` / `ssh-keygen`）。Windows 11 には標準で入っています。
  * 鍵は `just deploy` が自動生成します（`natgw_key` / `natgw_key.pub`）。**秘密鍵 `natgw_key` は絶対にコミットしないでください**（`.gitignore` 済み）。
* Step4 の **踏み台（bastion）／多段 SSH（`ssh -J` / ProxyJump）** を理解していること。本ステップでも private VM へは踏み台越しに入ります（確認のための手段。主役は egress）。

## 構成されるリソース
`main.bicep` ファイルにより、以下のリソースがデプロイされます。
* **リソースグループ**: `rg-network-learn-natgw` (東日本リージョン)
* **VNet**: `vnet-natgw` (10.0.0.0/16)
  * **公開ゾーン** `subnet-bastion` (10.0.0.0/24) … 確認用の踏み台を置く
    * **踏み台 VM** `vm-bastion`: パブリック IP あり。SSH(22) を**自分のグローバル IP からのみ**許可。
  * **非公開ゾーン** `subnet-private` (10.0.1.0/24) … 保護対象を置く
    * **private VM** `vm-private`: **パブリック IP なし**。inbound は踏み台サブネットからの SSH だけ許可（＝受信は閉じている）。
    * **NAT Gateway** `natgw` (+ パブリック IP `pip-natgw`) をこのサブネットに関連付け … **送信専用の出口**。
    * このサブネットは **`defaultOutboundAccess: false`**：Azure 暗黙の送信アクセスを無効化し、「出口＝NAT Gateway だけ」にしている。だから NAT Gateway を外すと外へ出られなくなる。
* どちらの VM も**公開鍵認証のみ**。private VM へは Step4 と同じく `ssh -J`（踏み台越し）で入ります。

### 構成イメージ
```
        [あなたのPC] ──SSH(22)──▶ vm-bastion (public IP)  ※確認用の入口（Step4 と同じ）
                                       │ ssh -J で中継
                                       ▼
   ┌──────────── vnet-natgw (10.0.0.0/16) ────────────┐
   │  subnet-private (10.0.1.0/24) = 非公開ゾーン       │
   │     vm-private 10.0.1.x  [public IP なし]          │
   │        │ 受信：踏み台サブネットからの SSH だけ        │  ← inbound は閉じている
   │        │ 送信：↓                                   │
   │        ▼                                          │
   │     [ NAT Gateway natgw + pip-natgw ]  ───────────┼──▶ インターネット
   │        outbound だけを 1 つの出口(SNAT)に集約        │     （外から見た送信元 = pip-natgw）
   └──────────────────────────────────────────────────┘
```

---

## 実行手順

コマンドはすべてこの `step5` ディレクトリで実行してください。

### 1. リソースのデプロイ
SSH 鍵の自動生成 → 自分のグローバル IP の取得 → デプロイ、までを一括で行います。
VM 2 台＋NAT Gateway を作るため、完了まで数分かかります。
```bash
just deploy
```
> `nsg-bastion` の SSH 許可元には、実行時のあなたのグローバル IP が自動で設定されます。

### 2. 出口（NAT Gateway）の確認
各 VM の IP と、NAT Gateway のパブリック IP（＝private VM の出口アドレス）を表示します。
`vm-private` にパブリック IP が無いこと、それでも出口となる NAT Gateway の IP があることを確認します。
```bash
just info
```

### 3. private VM の外向き通信を確認し、SNAT を体感する（成功テスト）
踏み台越しに private VM へ入り、「インターネットから見た自分の送信元 IP」を問い合わせます（`curl https://api.ipify.org`）。
返ってくる IP は **NAT Gateway のパブリック IP と一致**します。パブリック IP を持たない VM の送信が、
1 つの出口（SNAT）に集約されていることが分かります。
```bash
just test-egress
```
> `MATCH -> outbound is consolidated to the NAT Gateway (SNAT).` と表示されれば成功です。
> 受信の入口は一切開けていない（パブリック IP なし）のに、送信はできている＝**inbound と outbound は別物**。

実際の OS パッケージ取得でも egress を確認したい場合（NAT Gateway が無いと通りません）。
```bash
just test-apt        # private VM で sudo apt-get update を実行
```

### 4. NAT Gateway を外すと外へ出られなくなることの確認（失敗テスト）
`subnet-private` から NAT Gateway の関連付けを外します。`defaultOutboundAccess: false` のため、
出口が無くなり egress が成立しなくなります。
```bash
just detach-nat
```
外した後にもう一度 `just test-egress` を実行すると、egress が**失敗**します（タイムアウトで送信元 IP が空）。
→ 外へ出られていたのは **NAT Gateway が出口を提供していたから**だと分かります。
> 注意：inbound 側（踏み台越しの SSH）はこの間も変わらず通ります。**止まったのは outbound だけ**であることも確認できます。

### 5. NAT Gateway を戻して再び外へ出られるようにする
関連付けを戻すと、再び egress が成立し、送信元 IP も再び NAT Gateway の IP に一致します。
```bash
just attach-nat
```
その後 `just test-egress` を実行すると、再び**成功**します。

### 6. （任意）自分の IP が変わって踏み台に入れなくなったとき
別の回線・Wi-Fi に移ってグローバル IP が変わると、踏み台に SSH できなくなります。現在の IP で許可を更新します。
```bash
just update-myip
```

### 7. リソースの削除 (クリーンアップ)
```bash
just destroy
```
> ローカルの鍵 `natgw_key` / `natgw_key.pub` は残ります。不要なら手動で削除してください。
