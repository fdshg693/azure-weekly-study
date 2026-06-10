# Step 6 で登場した用語・概念

このステップで**新たに**登場した用語・概念をまとめます。
VNet・サブネット・NSG・VM・パブリック IP の有無による隔離・送信元限定（最小権限）・
踏み台／多段 SSH（`ssh -J` / ProxyJump）・公開鍵認証など、Step 1〜5 でカバーした内容は前提として含めません。

## ネットワーク全般の概念

### マネージドな踏み台（managed jump host / bastion as a service）
* 「踏み台（bastion / jump box）」は **役割（プライベートなホストへ入るための中継点）** であって、必ずしも自前の VM である必要はない。
* Step4 では踏み台を**自前 VM**で実装した：OS のパッチ当て、sshd の設定（`AllowTcpForwarding`）、SSH の公開範囲、鍵管理を**すべて自分で**持つ。踏み台 VM 自体が攻撃対象（=守るべき資産）にもなる。
* これをクラウド事業者の**マネージドサービス**に肩代わりさせると、踏み台の OS・中継ソフトの運用責任が事業者側へ移る。利用者は「どの VM に・誰が入れるか」という**認可（認証・権限）**に集中できる。
* トレードオフ：**運用の手離れ**と引き換えに、**時間課金のコスト**と**サービス固有の制約**（専用サブネット名・接続方法など）を受け入れる。「自分で持つ／借りる」の典型的な判断。

### 「踏み台の正体が変わっても、最小権限の構図は不変」
* Step4・Step6 とも、保護対象 VM（パブリック IP なし）の NSG は「**踏み台が居るサブネットからの SSH だけ許可**」という最小権限で守る。
* 変わるのは**送信元レンジ**だけ：Step4 は自前踏み台のサブネット、Step6 は **AzureBastionSubnet**。
* つまり「誰が踏み台か」は実装の違いで、「private への入口を 1 か所に絞り、そこからの通信だけ許す」という設計思想は同じ。`lock-private` / `unlock-private` で「最終的に通しているのは NSG の許可」だと確認できるのも両ステップ共通。

### 「インターネットに開いた管理ポート」を無くすという発想
* Step4 の自前踏み台は、たとえ自分の IP に絞っても**インターネットに面した 22 番**を持っていた（攻撃面が残る）。
* マネージドな踏み台では、利用者は**事業者の認証済みコントロールプレーン（CLI / ポータル）経由**で踏み台に到達する。生の SSH ポートを公開しないので、「自分の IP を許可リストに登録する」運用自体が不要になる（IP が変わるたびの更新も不要）。
* これは「ネットワーク到達性（IP で開ける）」ではなく「**ID/認可で開ける**」へ寄せる考え方。ゼロトラスト的な管理アクセスの一例。

## Azure 固有の用語（上記概念の具体例）

### Azure Bastion（マネージドな踏み台サービス）
* **Azure Bastion** は、VNet 内に配置するマネージドな踏み台サービス。パブリック IP を持たない VM へ、**踏み台 VM を自分で立てずに** SSH/RDP で到達できる。
* 接続元（利用者）から見ると、生の SSH ポートに直接つなぐのではなく、**Azure の認証済みセッション**を介して Bastion に到達し、Bastion が VNet 内から対象 VM の**プライベート IP:22** へ中継する。
* **SKU**：Developer / Basic / Standard / Premium がある。本ステップは **Standard** を使用（後述のネイティブクライアント＝CLI 接続のため）。
* 課金は**デプロイされている時間に対して発生**する（＋データ転送）。常時稼働だと小さな踏み台 VM より割高なので、学習では使い終わったら削除する。

### `AzureBastionSubnet`（予約名の専用サブネット）
* Azure Bastion は、**名前がちょうど `AzureBastionSubnet` のサブネット**に配置する必要がある（この名前以外には置けない）。
* **最小サイズは /26**（Standard 以上では /26 以上が必要）。Bastion 専用に空けておき、**ここに VM は置かない**。
* 通常このサブネットに **NSG は不要**（Azure が必要な通信を内部で管理する）。NSG を付ける場合は Microsoft が定める必須ルール一式（GatewayManager からの 443 受信など）が要るため、設定を誤ると Bastion が壊れる。学習では付けない。

### ネイティブクライアント接続（`enableTunneling` / `az network bastion ssh` / `tunnel`）
* Azure Bastion は本来ブラウザ（ポータル）から接続するが、**ネイティブクライアント対応**を有効にすると、ローカルの `ssh` クライアントや `az` CLI から接続できる。
* これには **Standard SKU ＋ `enableTunneling: true`** が必要（本ステップの bicep で有効化）。
* CLI コマンド：
  * `az network bastion ssh ... --target-resource-id <VM の ID> --auth-type ssh-key --username <user> --ssh-key <秘密鍵>` … Bastion 越しに対話 SSH。
  * `az network bastion tunnel ... --resource-port 22 --port 50022` … ローカルポート(50022)を対象 VM の 22 番へ転送するトンネルを張る。あとは `ssh -p 50022 user@127.0.0.1` で入れる（スクリプト化や scp に便利）。
* 接続先 VM は**プライベート IP やパブリック IP ではなく「リソース ID」で指定**する点が、これまでの IP 直打ち SSH と異なる（だから bicep で `vm-private` の ID を出力している）。

### private VM 側の NSG 許可元が `AzureBastionSubnet` になる
* Bastion は AzureBastionSubnet 内のホストとして対象 VM の 22 番へ接続するため、private VM の NSG は **送信元 = `10.0.0.0/26`（AzureBastionSubnet）** からの SSH を許可する。
* Step4 では送信元が「自前踏み台サブネット」だった。**送信元レンジが変わるだけ**で、最小権限ルールの形は同じ。
* `just lock-private`（このルール削除）→ Bastion 接続も失敗、`just unlock-private`（復元）→ 成功、という対比で「通しているのは NSG 許可」だと確認できる（Step4 と同じ検証手法）。

## このステップの要点
* 「踏み台」は**役割**であり、自前 VM でも**マネージドサービス（Azure Bastion）**でも実現できる。後者は踏み台 VM の OS・中継基盤の**運用責任を事業者へ移譲**できる代わりに、**時間課金**と**サービス固有の制約**を受け入れる。
* Azure Bastion は **`AzureBastionSubnet`（予約名・/26 以上）** に置き、Standard SKU ＋ `enableTunneling` でローカル `ssh` / `az network bastion ssh|tunnel` から接続できる。接続先は **VM のリソース ID** で指定する。
* 利用者は**生の SSH ポートにつながず、認証済み Azure セッション経由**で到達する。よって Step4 のような「自分のグローバル IP を NSG に登録する」運用が不要になる（攻撃面の縮小／IP 変更への強さ）。
* それでも最終的な許可は **private VM の NSG**（送信元 = `AzureBastionSubnet`）が握る。`lock-private` / `unlock-private` で因果を確認できるのは Step4 と同じ。
* ゴール（パブリック IP の無い VM へ安全に入る）は Step4 と同一。違いは **誰が踏み台を管理し・どう認証し・いくらかかるか**——「自分で持つ vs 借りる」の判断軸を体感するのが本ステップ。
