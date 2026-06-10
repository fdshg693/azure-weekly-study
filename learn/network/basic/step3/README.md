# Step 3: Hub-Spoke 構成と UDR によるルーティング制御

このステップでは、中央の **ハブ VNet** と 2 つの **スポーク VNet** からなる Hub-Spoke 構成を作り、
**ピアリングは推移しない**（spoke 同士は直接つながらない）ことを体感したうえで、
**UDR（ユーザー定義ルート）** と **NVA（中継 VM）** を使って spoke 間通信を成立させます。

## 目的
* ピアリングは **推移的でない**こと（hub↔spoke1・hub↔spoke2 があっても spoke1↔spoke2 は通信できない）を理解する。
* **ルートテーブル（UDR）** で「相手 spoke 宛ては NVA 経由」と経路を上書きし、通信を成立させる方法を学ぶ。
* **NVA（IP フォワーディングを有効にした VM）** がルーターとして中継する仕組みを理解する。
* ピアリングの **`allowForwardedTraffic`**（Step2 では false にしていた）を true にする意味を、実際に転送が起きる構成で理解する。

## 前提条件
* [Azure CLI](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli) (事前に `az login` でログイン済みであること)
* [Just](https://github.com/casey/just)

## 構成されるリソース
`main.bicep` ファイルにより、以下のリソースがデプロイされます。
* **リソースグループ**: `rg-network-learn-hubspoke` (東日本リージョン)
* **ハブ VNet**: `vnet-hub` (10.0.0.0/16) / サブネット: `subnet-nva` (10.0.0.0/24)
  * **NVA**: `vm-nva` (プライベート IP `10.0.0.4` 固定、パブリック IP なし)
    * NIC で `enableIPForwarding = true`、OS 側でも cloud-init により `net.ipv4.ip_forward = 1` を有効化し、ルーターとして動作する。
* **スポーク1 VNet**: `vnet-spoke1` (10.1.0.0/16) / サブネット: `subnet-spoke1` (10.1.0.0/24)
  * **VM**: `vm-spoke1` (パブリック IP あり、疎通テストの起点)
  * **ルートテーブル** `rt-spoke1`: 「10.2.0.0/16（spoke2）宛ては NVA(10.0.0.4) へ」
* **スポーク2 VNet**: `vnet-spoke2` (10.2.0.0/16) / サブネット: `subnet-spoke2` (10.2.0.0/24)
  * **VM**: `vm-spoke2` (**パブリック IP なし**、隔離された宛先)
  * **ルートテーブル** `rt-spoke2`: 「10.1.0.0/16（spoke1）宛ては NVA(10.0.0.4) へ」
* **VNet ピアリング**: hub↔spoke1、hub↔spoke2 の 2 組（**spoke1↔spoke2 はあえて作らない**）
* **NSG**: 各サブネットに適用（詳細は `KNOWLEDGE.md`）

### 構成イメージ
```
            ┌──────────── vnet-hub (10.0.0.0/16) ────────────┐
            │            vm-nva (10.0.0.4) = NVA / ルーター     │
            └───────▲───────────────────────────▲────────────┘
              peering│ (forwarded許可)     peering│ (forwarded許可)
            ┌───────┴────────┐          ┌────────┴───────┐
            │ vnet-spoke1    │          │ vnet-spoke2    │
            │ (10.1.0.0/16)  │   ✕ 直接  │ (10.2.0.0/16)  │
            │ vm-spoke1      │ ピアリング  │ vm-spoke2      │
            │ +rt-spoke1     │   無し    │ +rt-spoke2     │
            └────────────────┘          └────────────────┘
   spoke1 → spoke2 は UDR により NVA を経由して通信する
```

---

## 実行手順

コマンドはすべてこの `step3` ディレクトリで実行してください。

### 1. リソースのデプロイ
```bash
just deploy
```
VM 3 台とピアリング・ルートテーブルを作成するため、完了まで数分かかります。
NVA の IP フォワーディングは cloud-init で起動時に有効化されます。

### 2. spoke 間の疎通確認（UDR + NVA 経由）
spoke1 から spoke2 のプライベート IP へ ping を実行し、**成功する**ことを確認します。
直接ピアリングは無いため、この通信は UDR によって NVA 経由でルーティングされています。
```bash
just test-peering
```
> 成功すれば、UDR と NVA による中継が機能していることになります。

### 3. 経路の確認（NVA を経由していることの証明）
`tracepath` で経路をたどり、途中に **NVA(10.0.0.4)** が現れることを確認します。
これにより「直接届いている」のではなく「NVA を経由している」ことが目で見て分かります。
```bash
just trace-route
```

また、spoke1 の NIC の **有効なルート**を確認すると、`10.2.0.0/16 → VirtualAppliance` という UDR が効いていることが分かります。
```bash
just show-routes
```

### 4. UDR を消すと通信が止まることの確認（失敗テスト）
ルートテーブルから `to-spoke2` のルートを削除します。すると spoke1 は spoke2 への経路を失い、通信できなくなります。
```bash
just disable-route
```
削除後にもう一度 `just test-peering` を実行すると、ping が**失敗（タイムアウト）**します。
→ **ピアリングだけでは spoke 同士は通信できず、UDR が経路を成立させていた**ことが確認できます。

### 5. UDR を戻して通信を復活させる
ルートを再作成すると、再び spoke1→spoke2 の通信が通るようになります。
```bash
just enable-route
```
その後 `just test-peering` を実行すると、再び ping が**成功**します。

### 6. インターネットからの隔離の確認（任意）
ローカル PC から spoke2 のプライベート IP へ ping を実行し、**失敗すること**を確認します。
spoke2 にはパブリック IP が無いため、成功した spoke1 からの ping が確実にプライベート経路経由であることを担保します。
```bash
just test-local-fail
```

### 7. リソースの削除 (クリーンアップ)
```bash
just destroy
```
