# Step 6: マネージドな踏み台 — Azure Bastion

Step4 では「踏み台（jump box）」VM を**自前で**立て、自分のグローバル IP にだけ SSH(22) を開き、
`ssh -J`（ProxyJump）で奥の private VM（パブリック IP なし）へ多段 SSH しました。

このステップは同じゴール（パブリック IP を持たない VM へ安全に入る）を、
踏み台 VM を自分で持たずに **マネージドサービス Azure Bastion** に肩代わりさせて実現します。
Step4 の自前踏み台との **手触り・コスト・管理責任の違い**を対比で体感するのが狙いです。

## 目的
* **「踏み台」という役割そのものはサービスに委譲できる**ことを理解する：踏み台 VM の OS パッチ当て・sshd 設定・SSH 公開を自分で持たずに、private VM へ到達する。
* **Azure Bastion** を専用サブネット `AzureBastionSubnet` に配置し、パブリック IP を持たない VM へ接続する。
* **Step4 の `ssh -J`（手組み）との対比**を体感する：
  * 踏み台 VM が無い（管理対象が 1 台減る）。
  * **自分のグローバル IP を NSG に登録しない**（インターネットに開いた 22 番が存在しない）。利用者は Azure の認証済みセッション（CLI／ポータル）で到達する。
  * その代わり Azure Bastion は**時間課金**で、手組みの小さな踏み台 VM よりコストが高い。
* private VM 側の NSG が許可する送信元が「踏み台サブネット」から「**AzureBastionSubnet**」に変わるだけで、最小権限の考え方は Step4 と同じであることを確認する。

## 前提条件
* [Azure CLI](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli)（事前に `az login` 済み、かつ `az network bastion ssh/tunnel` が使える比較的新しいバージョン）
* [Just](https://github.com/casey/just)
* **OpenSSH クライアント**（`ssh` / `ssh-keygen`）。Windows 11 には標準で入っています。
  * 鍵は `just deploy` が自動生成します（`azbastion_key` / `azbastion_key.pub`）。**秘密鍵 `azbastion_key` は絶対にコミットしないでください**（`.gitignore` 済み）。
* Step4 の **自前踏み台／多段 SSH（`ssh -J` / ProxyJump）** を理解していること。本ステップはそれを「マネージド化したらどう変わるか」を見る回です。

> **コスト注意**：Azure Bastion（Standard）は**起動している間ずっと時間課金**されます（手組みの `Standard_B1s` 踏み台より高い）。検証が済んだら必ず `just destroy` で削除してください。

## 構成されるリソース
`main.bicep` ファイルにより、以下のリソースがデプロイされます。
* **リソースグループ**: `rg-network-learn-azbastion`（東日本リージョン）
* **VNet**: `vnet-azbastion` (10.0.0.0/16)
  * **`AzureBastionSubnet`** (10.0.0.0/26) … Azure Bastion 専用の**予約名**サブネット（名前固定・/26 以上）。VM は置かない。
    * **Azure Bastion** `azbastion`（Standard SKU・トンネリング有効）＋ 公開 IP `pip-azbastion`（Standard/Static）… マネージドな踏み台。
  * **非公開ゾーン** `subnet-private` (10.0.1.0/24)
    * **private VM** `vm-private`: **パブリック IP なし**。inbound は **AzureBastionSubnet (10.0.0.0/26) からの SSH だけ**許可。
* private VM は**公開鍵認証のみ**。踏み台 VM は存在せず、中継の責務は Azure Bastion 側が持ちます（Step4 の `AllowTcpForwarding` 設定は不要）。

### 構成イメージ
```
   [あなたのPC]
      │ az network bastion ssh / tunnel（Azure の認証済みセッション経由）
      ▼
   ┌──────────── vnet-azbastion (10.0.0.0/16) ────────────┐
   │  AzureBastionSubnet (10.0.0.0/26)                     │
   │     [ Azure Bastion azbastion + pip-azbastion ]       │  ← マネージドな踏み台（VM ではない）
   │            │ 内部から SSH(22) で中継                    │
   │            ▼                                          │
   │  subnet-private (10.0.1.0/24) = 非公開ゾーン            │
   │     vm-private 10.0.1.x  [public IP なし]              │
   │        受信：AzureBastionSubnet からの SSH だけ許可      │
   └──────────────────────────────────────────────────────┘
```

> Step4 との違い：Step4 では `[あなたのPC] ──SSH(22, 自分のIPのみ)──▶ vm-bastion(public IP) ──ssh -J──▶ vm-private`
> でした。本ステップは `vm-bastion` が消え、代わりにマネージドな Azure Bastion が中継します。

---

## 実行手順

コマンドはすべてこの `step6` ディレクトリで実行してください。

### 1. リソースのデプロイ
SSH 鍵の自動生成 → デプロイ、までを一括で行います。**Azure Bastion の作成に数分〜10分程度**かかります。
```bash
just deploy
```
> Step4 と違い、**自分のグローバル IP を渡す必要はありません**。インターネットに開いた SSH ポートが無く、
> アクセスは Azure の認証済みセッション（`az login` 済みの CLI／ポータル）で行うためです。

### 2. 「踏み台 VM が無い」ことの確認
private VM にパブリック IP が無いこと、そして**踏み台 VM が存在せず**、踏み台の役割を
マネージドな Azure Bastion が担っていることを確認します。
```bash
just info
```

### 3. Azure Bastion 越しに private VM へ入る（成功テスト）
マネージドな踏み台越しに、パブリック IP を持たない private VM へ接続します。
```bash
just connect      # 対話シェル。`hostname` などを実行し、`exit` で抜ける
```
スクリプトで「確かに到達した」ことだけ確認したい場合は、Bastion トンネルを一時的に張って
ワンショットでコマンドを実行します（張る → 実行 → 自動で撤去）。
```bash
just test
```
> `--- reached vm-private via Azure Bastion (managed) ---` と private VM の hostname が表示されれば成功です。
> Step4 の `ssh -J` と**結果は同じ**（パブリック IP の無い VM に入れた）ですが、途中に**自前の踏み台 VM が無い**のが違いです。

### 4. NSG を閉じると Bastion でも入れなくなることの確認（失敗テスト）
private VM の NSG から「AzureBastionSubnet からの SSH 許可」を外します。
```bash
just lock-private
```
その後 `just connect`（または `just test`）を実行すると**失敗**します。
→ Azure Bastion を使っても、最終的に通しているのは **private VM 側の NSG 許可**だと分かります
（Step4 の `lock-private` と同じ考え方。送信元が踏み台サブネットから AzureBastionSubnet に変わっただけ）。

### 5. NSG を戻して再び入れるようにする
```bash
just unlock-private
```
その後 `just connect` で再び**成功**します。

### 6. リソースの削除（クリーンアップ）
Azure Bastion は時間課金です。検証が終わったら必ず削除してください。
```bash
just destroy
```
> ローカルの鍵 `azbastion_key` / `azbastion_key.pub` は残ります。不要なら手動で削除してください。

---

## Step4（自前踏み台）と Step6（Azure Bastion）の対比まとめ

| 観点 | Step4: 自前踏み台 VM ＋ `ssh -J` | Step6: Azure Bastion（マネージド） |
|------|-------------------------------|----------------------------------|
| 踏み台の実体 | 自分で立てた VM（`vm-bastion`） | Azure のマネージドサービス（VM 管理不要） |
| 管理責任 | OS パッチ・sshd 設定・鍵を**自分で**持つ | Azure が中継基盤を管理 |
| インターネットへの公開 | 踏み台の 22 番を**自分の IP に**開く（NSG に IP 登録） | 開いた SSH ポート無し。認証済み Azure セッションで到達 |
| 接続手段 | ローカルの `ssh -J`（ProxyJump） | `az network bastion ssh` / ポータル / トンネル |
| コスト | 小さな VM（停止すれば安い） | **時間課金**（常時稼働だと割高） |
| private VM の NSG 許可元 | 踏み台サブネット | **AzureBastionSubnet** |

「最小権限で private VM に入る」というゴールは同じ。**誰が踏み台を管理し、どう認証し、いくらかかるか**が違う、というのが本ステップの要点です。
