# KNOWLEDGE — `simple` で新たに出た用語・概念

> VNet / Subnet / NSG / Public IP / NIC といったネットワークの基礎は network トピックで
> カバー済みのため、ここでは **VM（IaaS）固有** の概念に絞る。

## SSH 鍵認証（パスワードレス）
- 公開鍵を VM の `~/.ssh/authorized_keys` に置き、秘密鍵を持つ人だけがログインできる方式。
- Bicep の `linuxConfiguration.disablePasswordAuthentication: true` で**パスワード認証を無効化**し、
  `ssh.publicKeys` に公開鍵を渡している。パスワード総当たりのリスクをそもそも無くせる。

## VM の電源状態と課金（`stop` vs `deallocate`）
- **Running**: 動作中。コンピュート課金あり。
- **Stopped（allocated）**: OS はシャットダウンだが**ハードウェアの割り当ては維持** → **コンピュート課金は続く**。
  `az vm stop` がこの状態。
- **Stopped (deallocated)**: 割り当てを解除 → **コンピュート課金が止まる**（ディスク等のストレージ課金は残る）。
  `az vm deallocate` がこの状態。**課金を止めたいなら deallocate**、が要点。

## Public IP の払い出し方式（Dynamic vs Static）と SKU
- **Dynamic**: VM が起動している間だけ IP が割り当てられ、**deallocate で解放**される。
  再起動すると**別の IP になりうる**。Basic SKU の既定。
- **Static**: 一度決まった IP が**固定**され、deallocate しても保持される。Standard SKU は Static のみ。
- このプロジェクトは既定を Basic+Dynamic にして「再起動で IP が変わる」を観察できるようにし、
  パラメータで Standard+Static に切り替えると固定される対比を用意している。

## Managed Disk（OS ディスク）
- VM の OS が乗る仮想ディスク。ストレージアカウントを意識せず Azure が管理する。
- `osDisk.createOption: 'FromImage'` で Marketplace イメージから複製して作る。
  `storageAccountType`（例 `Standard_LRS`）で性能・冗長性を選ぶ。VM を消してもディスクは残りうる（課金注意）。

## Marketplace イメージ（imageReference）
- `publisher / offer / sku / version` の 4 点で OS イメージを指定する（例: Canonical の Ubuntu 22.04 LTS gen2）。
- `version: 'latest'` で最新パッチ済みイメージを使う。「焼いたイメージから複製」する発想は Step 5 の
  カスタムイメージ（Shared Image Gallery）につながる。

## VM Run Command（`az vm run-command invoke`）
- SSH で入らずに、Azure の管理プレーン経由で VM 内のシェルスクリプトを実行する仕組み。
- このプロジェクトでは nginx のインストールに使用（`RunShellScript`）。NSG で 22 を閉じていても実行できるのが特徴。

## B シリーズ（バースト可能 VM）
- `Standard_B1s` など。普段は低い CPU で「クレジット」を貯め、必要時に一時的に高い性能を出せる安価なサイズ。
  学習・検証用途に向く。
