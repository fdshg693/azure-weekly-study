# 仮想マシン（VM / IaaS）学習プラン — 何から作るか

このファイルは vm トピックの**プロジェクト設計の目安（ロードマップの正本）**。
このトピックはまだプロジェクトが無いので、ここでは「最初の最小構成 → どう深化させるか」を定める。
方針はリポジトリ共通（[../CLAUDE.md](../CLAUDE.md)）どおり:
「**一般概念／最小構成 → 実装 → 設定を出し入れして因果を確かめる**」「**構築・実行はユーザー自身が行い、AI は Azure 上で実行しない**」。

> 関連トピック: **マネージド DB（PaaS）** 側は [../db/PLAN.md](../db/PLAN.md)。
> network / storage トピックでは VM を「到達確認の道具」として既に少し使っている。
> ここでは **VM そのもの（IaaS）を主役**にし、「OS から自分で面倒を見る代わりに何が自由になるか」を学ぶ。

---

## 1. このトピックで学びたいこと（ゴール像）

VM は最も基本的な IaaS。マネージドサービス（func / Logic Apps / AKS / マネージド DB）と対比して、
**「どこまで自分の責任か」の境界**を体で覚えるのが狙い。

- **VM の構成要素**: VM 本体 / OS ディスク・データディスク（Managed Disk）/ NIC / Public IP / NSG / VNet・Subnet の関係。
- **接続と認証**: SSH 鍵認証（パスワードレス）、**NSG による到達制御**、Bastion / Just-In-Time アクセス。
- **イメージとプロビジョニング**: Marketplace イメージ、**cloud-init / カスタムスクリプト拡張**による初期セットアップ自動化。
- **ID とキーレス化**: VM の **Managed Identity** で他リソース（Storage / Key Vault / DB）へキーレスアクセス（auth トピックの延長）。
- **スケールと可用性**: VM サイズ変更、可用性ゾーン、**VM Scale Sets（VMSS）** の考え方（触りだけ）。
- **コスト管理**: 起動 / 停止（割り当て解除）と課金の関係。

## 2. 推奨ロードマップ（やさしい順）

各プロジェクトは `learn/vm/{name}/` に置く想定。「**1 プロジェクト = 主役の概念 1〜2 個**」に絞る。

### Step 1 — `simple`（Linux VM を 1 台立てて入る）
**主役**: VM + ネットワーク一式の最小構成と SSH 接続。
- Bicep で VNet / Subnet / NSG / Public IP / NIC / Linux VM を作り、**SSH 鍵**でログイン。
- **因果を確かめる実験**: NSG の 22 番ルールを削る → SSH 不可、足す → 可。`80` を開けて簡単な Web サーバーを立て、開閉で到達が変わるのを観察。
- **停止（割り当て解除）と課金**: `deallocate` と `stop` の違い、再起動で Public IP がどう変わるかを確認。

### Step 2 — `cloud-init`（プロビジョニング自動化が主役）
**主役**: cloud-init / カスタムスクリプト拡張による初期セットアップの自動化。
- 起動時に nginx などを自動インストール・設定し、「立てたら即動く」状態を作る。
- **因果を確かめる実験**: cloud-init の内容を変えて作り直し、手動 SSH 設定との差（再現性・冪等性）を体感。
  「**Pet（手なずける）vs Cattle（使い捨て）**」という IaaS の考え方に触れる。

### Step 3 — `managed-identity`（VM からのキーレスアクセスが主役）
**主役**: VM の Managed Identity による他リソースへのキーレスアクセス。
- VM に System-assigned / User-assigned ID を付け、**Storage か Key Vault** へ接続文字列なしでアクセス。
- **因果を確かめる実験**: ロール割り当てを付け外し → VM からのアクセスが 403 ⇄ 成功に変わる。
  auth・func・k8s で繰り返した「**認証と認可は別**」を VM でも再確認。

### Step 4 — `db-on-vm`（自前 DB と マネージド DB の対比）
**主役**: VM 上に PostgreSQL を自前構築し、db トピックのマネージド DB と比較。
- VM に PostgreSQL を入れ、データディスクに配置。バックアップ・パッチ・可用性を**自分で**面倒見る体験。
- **因果を確かめる実験**: 同じ「DB に接続して使う」を [../db/PLAN.md](../db/PLAN.md) のマネージド版と並べ、
  「**PaaS で何を失い、IaaS で何を背負うか**」（パッチ / バックアップ / スケール / 可用性の責任分界）を言語化する。

### Step 5（発展）— `vmss` / Bastion / イメージ化
- **VM Scale Sets** でスケールアウトとロードバランサ、AKS のノードプールとの関係を理解。
- **Bastion / Just-In-Time** で Public IP を晒さない安全な接続。
- カスタムイメージ（Shared Image Gallery）で「焼いたイメージから複製」する Cattle 運用へ。

## 3. 進め方のメモ

- 各プロジェクトに共通構成（`README.md` / `KNOWLEDGE.md` / `justfile` または `Taskfile.yml`）を置く。複雑になったら Taskfile。
- **コスト注意**: VM は立てっぱなしで課金が嵩むサービス。各 README に「使い終わったら `deallocate` / 破棄」を明記し、実験後の停止を習慣化する。
- network / storage / db / auth トピックの資産（VNet・NSG・Private Endpoint・Managed Identity）と接続すると、IaaS が他サービスの土台であることが見えてくる。
- 最初のプロジェクトを 1 つ追加したタイミングで `learn/vm/CLAUDE.md` に習熟度を記録する。
