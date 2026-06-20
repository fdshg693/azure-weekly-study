# Step 1: `simple` — Linux VM を 1 台立てて SSH で入る

vm トピックの最初のプロジェクト（[../PLAN.md](../PLAN.md) の Step 1）。
**VM（IaaS）そのものを主役**に、VM を動かすのに最低限必要なネットワーク一式を Bicep で作り、
**SSH 鍵**でログインする。マネージドサービス（func / Logic Apps / AKS / マネージド DB）と違い、
ここから先は **OS の中身は自分の責任**になる、という境界を体で覚えるのが狙い。

## 目的（このステップで体感すること）

- VM を 1 台動かすのに必要な構成要素（**VNet / Subnet / NSG / Public IP / NIC / VM**）の関係を理解する。
- **SSH 鍵認証（パスワードレス）**で入る。パスワード認証は Bicep で無効化済み。
- **NSG による到達制御**を「出し入れして因果を確かめる」:
  - 22 番（SSH）を Deny → 入れない、Allow → 入れる。
  - 80 番（HTTP）を開けて簡単な Web サーバーを立て、開閉で到達が変わるのを見る。
- **停止（割り当て解除）と課金**: `stop` と `deallocate` の違い、Dynamic な Public IP が
  再起動でどう変わるかを確認する。

## 前提ツール

- [Azure CLI](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli)（`az login` 済み）
- [Just](https://github.com/casey/just)
- `ssh` / `ssh-keygen`（Windows は OpenSSH クライアント機能。`just keygen` が鍵を作る）

## 構成されるリソース（`main.bicep`）

| リソース | 名前 | 役割 |
|---|---|---|
| 仮想ネットワーク | `vnet-simple`（10.0.0.0/16） | VM が所属するネットワーク |
| サブネット | `subnet-simple`（10.0.0.0/24） | NSG を関連付ける単位 |
| NSG | `nsg-simple` | 受信フィルタ。初期は **SSH(22) のみ許可** |
| パブリック IP | `pip-simple` | 既定は **Basic + Dynamic**（IP 変化を観察するため） |
| NIC | `nic-simple` | VM をサブネット・Public IP につなぐ |
| 仮想マシン | `vm-simple` | Ubuntu 22.04 LTS / Standard_B1s / **SSH 鍵認証のみ** |

> リソースグループ: `rg-vm-learn-simple`（東日本）。

---

## 実行手順

すべてこの `simple` ディレクトリで実行する。

### 0. SSH 鍵の準備（無ければ作る）
```powershell
just keygen
```
`~/.ssh/id_ed25519(.pub)` を使う。既にあればそれを流用する。

### 1. デプロイ
手元の公開鍵を Bicep に渡して一式を作る。数分かかる。
```powershell
just deploy
```

### 2. SSH でログイン
```powershell
just ssh
```
パスワードを聞かれず、鍵だけで入れることを確認する（パスワードレス）。`exit` で抜ける。

---

### 実験1: NSG の SSH(22) で到達を切り替える
```powershell
just deny-ssh    # 22番を Deny
just ssh         # → タイムアウト（入れない）
just allow-ssh   # 22番を Allow に戻す
just ssh         # → また入れる
```
到達を決めていたのが **NSG の許可**だったことを対比で確認する。

### 実験2: 80番(HTTP)を開けて Web サーバーへ到達する
```powershell
just install-web   # VM 内に nginx を入れて起動（run-command 経由）
just open-http     # NSG に 80番許可を追加
just test-http     # → "hello from vm-simple" が返る
just close-http    # 80番許可を削除
just test-http     # → タイムアウト（VM 内で nginx は動いているのに届かない）
```
**「サーバープロセスが動いていること」と「NSG で到達できること」は別**だと体感する。

### 実験3: 停止（割り当て解除）と課金 / Public IP の変化
```powershell
just status        # 現在の電源状態
just stop          # シャットダウンするが allocated のまま → コンピュート課金は続く
just deallocate    # 割り当て解除 → コンピュート課金が止まる（Dynamic IP は解放）
just start         # 再起動。Dynamic な Public IP は別の値になりうる
just show-ip       # IP が変わったか確認
```
- **`stop` vs `deallocate`**: 止めても「割り当て」が残るとコンピュート課金は続く。課金を止めたいなら `deallocate`。
- **Public IP の変化**: 既定の **Basic + Dynamic** では deallocate で IP が解放され、`start` で別の IP になりうる。
  `main.bicep` の `publicIpSku=Standard` / `publicIpAllocation=Static` にすると **IP が固定**される（対比で確認できる）。

### 4. 後片付け（必ず実行）
```powershell
just destroy
```
> VM は立てっぱなしで課金が嵩む。実験が終わったら必ず削除（または `deallocate`）する。

## 補足

- このプロジェクトはパスワードレス・最小ネットワークが主眼。**プロビジョニング自動化（cloud-init）**は Step 2、
  **VM の Managed Identity によるキーレスアクセス**は Step 3 で扱う（[../PLAN.md](../PLAN.md)）。
- 新出の用語・概念は [KNOWLEDGE.md](./KNOWLEDGE.md)、構成図は [MERMAID.md](./MERMAID.md) を参照。
