# vm（仮想マシン / IaaS）トピック — ユーザーのレベル感と次プロジェクトの目安

このトピックは **VM（IaaS）そのもの** を主役に、`learn/vm/{name}/` の各プロジェクトで
段階的に学ぶ。共通方針はリポジトリ全体と同じ「**一般概念／最小構成 → 実装 → 設定を出し入れして
因果を確かめる**」「**構築・実行はユーザー自身、AI は Azure 上で実行しない**」。
次プロジェクトの設計の目安（ロードマップの正本）は [PLAN.md](./PLAN.md) を参照。

> network / storage トピックでは VM を「到達確認の道具」として使ってきたが、ここでは
> **VM 本体を主役**にし、マネージドサービスとの「責任分界」を学ぶ。

## プロジェクト一覧

### `simple` — Linux VM を 1 台立てて SSH で入る（PLAN Step 1）
Bicep で VNet / Subnet / NSG / Public IP / NIC / Linux VM(Ubuntu 22.04, B1s) を最小構成で作り、
**SSH 鍵認証（パスワードレス、`disablePasswordAuthentication`）**でログイン。
- **因果実験**: NSG の SSH(22) を Deny/Allow して到達が変わるのを確認（network step1 の ICMP 版と同型）。
- 80 番(HTTP)を開けて nginx を `run-command` で入れ、`open-http`/`close-http` で
  **「プロセスが動く」と「NSG で届く」は別**だと体感。
- **`stop` vs `deallocate`** の課金差、**Basic+Dynamic な Public IP が deallocate→start で変わる**
  （Standard+Static なら固定）をパラメータ切替で対比。

## 学習済みの概念
SSH 鍵認証（パスワードレス）、VM の電源状態（Running / Stopped-allocated / Deallocated）と
**stop と deallocate の課金差**、Public IP の **Dynamic vs Static**（再起動での IP 変化）、
Managed Disk（OS ディスク）、Marketplace イメージ（imageReference）、VM Run Command、B シリーズ。
（VNet/Subnet/NSG/NIC 等のネットワーク基礎は network トピックで習得済み。）

## まだ触れていない主要概念（PLAN の続き）
- **プロビジョニング自動化**: cloud-init / カスタムスクリプト拡張（Step 2、Pet vs Cattle）。
- **VM の Managed Identity** による他リソースへのキーレスアクセス（Step 3、auth/k8s の延長）。
- **自前 DB vs マネージド DB** の責任分界（Step 4、db トピックと対比）。
- **VMSS / Bastion / Just-In-Time / カスタムイメージ**（Step 5）。
- データディスク、可用性ゾーン、VM サイズ変更。
