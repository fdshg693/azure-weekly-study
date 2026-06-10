# Step 4: 踏み台（Bastion / Jump Box）越しのプライベート VM アクセス

このステップでは、**パブリック IP を持つ「踏み台」VM を 1 台だけ**インターネットに公開し、
その奥にいる**パブリック IP を持たない private VM**へ、踏み台を経由して（多段 SSH で）入る構成を作ります。

「インターネットに開くホストを最小限に絞り、保護対象は踏み台経由でしか触れない」という、
セキュリティの基本パターンを手で動かして学びます。

## 目的
* **踏み台（bastion / jump box）** の考え方を理解する：公開する入口を 1 つに集約し、内部ホストは直接公開しない。
* **多段 SSH（SSH ProxyJump / `ssh -J`）** で、踏み台を中継して private VM に入る方法を学ぶ。
* 踏み台への SSH を **自分のグローバル IP だけ**に絞り（入口の最小公開）、private VM への SSH を **踏み台サブネットだけ**に絞る（内部の最小権限）。
* private VM に **パブリック IP が無い**ことで「直接は入れない／踏み台経由でだけ入れる」ことを、成功・失敗の両方で確認する。

## 前提条件
* [Azure CLI](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli) (事前に `az login` でログイン済みであること)
* [Just](https://github.com/casey/just)
* **OpenSSH クライアント**（`ssh` / `ssh-keygen`）。Windows 11 には標準で入っています。
  * 鍵は `just deploy` が自動生成します（`bastion_key` / `bastion_key.pub`）。**秘密鍵 `bastion_key` は絶対にコミットしないでください**（`.gitignore` 済み）。

## 構成されるリソース
`main.bicep` ファイルにより、以下のリソースがデプロイされます。
* **リソースグループ**: `rg-network-learn-bastion` (東日本リージョン)
* **VNet**: `vnet-bastion` (10.0.0.0/16)
  * **公開ゾーン** `subnet-bastion` (10.0.0.0/24) … 踏み台を置く
    * **踏み台 VM** `vm-bastion`: **パブリック IP あり**、プライベート IP `10.0.0.4` 固定
      * cloud-init で **`AllowTcpForwarding yes` を明示**（`/etc/ssh/sshd_config.d/`）。`ssh -J` で踏み台が「private VM への TCP 接続を中継」するために必要な設定（Ubuntu の既定値は `yes` だが、踏み台の肝なので明示固定）。private VM は中継しないので、この設定は踏み台にだけ入れている。
    * **NSG** `nsg-bastion`: SSH(22) を **自分のグローバル IP からのみ**許可
  * **非公開ゾーン** `subnet-private` (10.0.1.0/24) … 保護対象を置く
    * **private VM** `vm-private`: **パブリック IP なし**（踏み台越しにしか入れない）
    * **NSG** `nsg-private`: SSH(22) を **踏み台サブネット(10.0.0.0/24)からのみ**許可
* どちらの VM も **公開鍵認証のみ**（パスワード認証は無効）。`just deploy` が作る同じ鍵を両方に入れ、ProxyJump で 1 本の秘密鍵で両ホップを認証します。

### 構成イメージ
```
            [あなたのPC]
                │ SSH (22) … 許可されるのは自分のグローバル IP だけ
                ▼
   ┌──────── vnet-bastion (10.0.0.0/16) ────────┐
   │  subnet-bastion (10.0.0.0/24) = 公開ゾーン   │
   │     vm-bastion 10.0.0.4  [public IP あり]    │  ← インターネットに開く唯一のホスト
   │                │ 内部 SSH（踏み台サブネット発）  │
   │                ▼                            │
   │  subnet-private (10.0.1.0/24) = 非公開ゾーン  │
   │     vm-private 10.0.1.x  [public IP なし]    │  ← 直接は入れない / 踏み台経由のみ
   └────────────────────────────────────────────┘
   あなたのPC → (踏み台) → private VM を「ssh -J」1 コマンドで貫通する
```

---

## 実行手順

コマンドはすべてこの `step4` ディレクトリで実行してください。

### 1. リソースのデプロイ
SSH 鍵の自動生成 → 自分のグローバル IP の取得 → デプロイ、までを一括で行います。
VM 2 台を作るため、完了まで数分かかります。
```bash
just deploy
```
> `nsg-bastion` の SSH 許可元には、実行時のあなたのグローバル IP が自動で設定されます。

### 2. private VM に「直接」入れないことの確認（失敗テスト）
private VM のプライベート IP に、ローカル PC から直接 SSH を試みます。**失敗（タイムアウト）**します。
パブリック IP が無く、そもそもインターネットから到達できる入口が存在しないためです。
```bash
just test-direct-fail
```
また、各 VM の IP 一覧を見ると、`vm-private` にパブリック IP が無いことが確認できます。
```bash
just info
```

### 3. 踏み台を経由して private VM に入る（多段 SSH・成功テスト）
`ssh -J`（ProxyJump）で踏み台を中継し、private VM に入ってコマンドを実行します。**成功**します。
```bash
just test-jump
```
> `--- reached the private VM via the bastion ---` と `vm-private` のホスト名が表示されれば、
> 踏み台越しに到達できたことになります。秘密鍵はあなたの PC から外に出ていません（後述）。

対話シェルで入りたい場合はこちら（`exit` で抜けます）。
```bash
just ssh-private      # 踏み台越しに private VM のシェルへ
just ssh-bastion      # 踏み台そのもののシェルへ
```

### 4. 踏み台経由の許可を外すと入れなくなることの確認（失敗テスト）
`nsg-private` から「踏み台サブネットからの SSH 許可」を削除します。すると踏み台からも private VM へ届かなくなります。
```bash
just lock-private
```
削除後にもう一度 `just test-jump` を実行すると、ジャンプが**失敗**します。
→ private VM に入れていたのは **NSG が踏み台サブネットからの SSH を許可していたから**だと分かります。

### 5. 許可を戻して再び入れるようにする
ルールを再作成すると、再び踏み台越しに入れるようになります。
```bash
just unlock-private
```
その後 `just test-jump` を実行すると、再び**成功**します。

### 6. （任意）自分の IP が変わって踏み台に入れなくなったとき
別の回線・Wi-Fi に移ってグローバル IP が変わると、`nsg-bastion` の許可元と一致せず踏み台に SSH できなくなります。
現在の IP で許可を更新します。
```bash
just update-myip
```

### 7. リソースの削除 (クリーンアップ)
```bash
just destroy
```
> ローカルの鍵 `bastion_key` / `bastion_key.pub` は残ります。不要なら手動で削除してください。
