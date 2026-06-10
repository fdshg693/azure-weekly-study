# Azure を通じてネットワークを学習

## ルート直下ファイル

- `README.md`（このファイル）

## 各ステップ共通ファイル構成

- `justfile`
    - just コマンドで利用するファイル
    - Azure でのネットワーク構築や通信確認などのコマンドをまとめる

- `KNOWLEDGE.md`
    - このステップで新たに出てきた用語・概念をまとめる
    - 前のステップでカバーした内容は含めない

- `README.md`
    - このステップで行う内容の説明や、学習の流れを記載する

- `MERMAID.md`
    - ネットワーク構成を mermaid 形式で表現するファイル
        - 複数の図を1ファイルにまとめて問題ない
        - 場合によっては、シナリオ単位で図をかき分けることで理解促進を図る

- `*.bicep`
    - Azure リソースをコードで定義するファイル
    - 可読性・理解のしやすさを最大限に優先して、必要なファイル分割を行う
        - 細かく分ければいいというものではなく、1ファイルにまとめた方が分かりやすい場合、多少責務違反が起きても1ファイルにまとめることもある

## ステップ一覧

`./step1`

仮想ネットワーク（VNet）、サブネット、ネットワークセキュリティグループ（NSG）、仮想マシン（VM）など、Azure の基本的なネットワークリソースの構築を学ぶ
ping コマンドを使用して仮想マシンとの疎通確認をして、NSG のルール変更によるアクセス制御（ICMP の許可・拒否）をテストする

## Step2

`./step2`

VNet ピアリングを使用して、2つの独立した仮想ネットワークを接続し、異なる VNet 間にある仮想マシン同士がプライベート IP アドレスで通信できることを学ぶ
Azure VM Run Command を使用して、仮想マシン内部から ping コマンドを実行し、VNet ピアリング経由での疎通を確認する

## Step3

`./step3`

ハブ&スポーク構成を作り、ピアリングが推移しない（スポーク同士は直接通信できない）ことを確認したうえで、ルートテーブル（UDR）と NVA（IP フォワーディングを有効にした中継 VM）を使ってスポーク間通信を成立させることを学ぶ
UDR の有効/無効を切り替えて、経路を成立させているのがピアリングではなく UDR であることを確認し、tracepath で実際に NVA を経由していることを検証する

## Step4

`./step4`

パブリック IP を持つ「踏み台（bastion / jump box）」VM を 1 台だけ公開し、その奥にいるパブリック IP を持たない private VM へ、踏み台を経由した多段 SSH（`ssh -J` / ProxyJump）で入る構成を学ぶ
踏み台への SSH を自分のグローバル IP だけに、private VM への SSH を踏み台サブネットだけに絞り（二層の最小権限）、直接 SSH は失敗・踏み台経由は成功となることを対比で確認する。NSG の許可を出し入れして、入れていたのが NSG の許可であることも検証する

## Step5

`./step5`

パブリック IP を持たない private VM の「外向き通信（egress / SNAT）」を、サブネットに関連付けた NAT Gateway で成立させる構成を学ぶ
「inbound を閉じる」と「outbound を許す」が別物であること、SNAT により外から見た送信元が NAT Gateway のパブリック IP に集約されることを `curl` で確認する。`defaultOutboundAccess: false` のうえで NAT Gateway を出し入れし、egress を成立させているのが NAT Gateway であることを対比で検証する（inbound 側の踏み台 SSH は終始変わらないことも確認）

## Step6

`./step6`

Step4 で自前 VM として手組みした「踏み台」を、マネージドサービス **Azure Bastion** に置き換え、パブリック IP を持たない private VM へ踏み台 VM 無しで入る構成を学ぶ
専用サブネット `AzureBastionSubnet`（予約名・/26 以上）に Azure Bastion を置き、`az network bastion ssh`/`tunnel` で接続する。Step4 の `ssh -J`（手組み）との手触り・コスト・管理責任の違い（踏み台 VM の運用が不要・生の SSH ポートを公開せず認証済みセッションで到達・時間課金）を対比で体感する。private VM の NSG 許可元が踏み台サブネットから `AzureBastionSubnet` に変わるだけで最小権限の構図は同じであることを `lock-private`/`unlock-private` で確認する

## Step7

`./step7`

Step1〜6 で「プライベート IP の直打ち」だった通信を、**Private DNS Zone による名前解決**に置き換える構成を学ぶ（PLAN の候補 F）
VNet 内だけで通用する独自ゾーン `corp.internal` を VNet にリンクし、VM のホスト名の**自動登録**（`registrationEnabled`）と**手動レコード**（別名）の 2 通りで「名前 → プライベート IP」を持たせ、`vm-b.corp.internal` のような名前で ping できることを確認する。`unlink`/`link` でリンクを出し入れし、「名前は引けないが IP では届く」対比で名前解決を担っているのが Private DNS Zone だと切り分ける（NSG/UDR/NAT GW の出し入れと同じ手法）。後続の候補 E（Private Endpoint/Private Link）の前提になる横断ステップ

## Step8

`./step8`

マネージドサービス（PaaS／Storage の blob）へ、公衆インターネットを経由せず **VNet 内のプライベート IP** で到達する構成を学ぶ（PLAN の候補 E）
自分のサブネットに **Private Endpoint**（PaaS への入口となる NIC）を生やし、公開エンドポイントと**同じ FQDN** を **Private DNS Zone `privatelink.blob.core.windows.net`** で**プライベート IP に解決**させる（Step7 の名前解決の延長で、向き先がプライベート IP になっただけ）。`Private DNS Zone Group` が PE の IP をゾーンへ自動登録する。Storage は `publicNetworkAccess: Disabled` で公開エンドポイントを閉じておく。検証は Run Command で、vm 上から公開 FQDN を解決して **`10.0.1.x`（PE のプライベート IP）** になることを確認する。`unlink`/`link`（名前解決の向き先）と `disable-public`/`enable-public`（公開エンドポイントの開閉）が**独立した 2 つのスイッチ**であることを出し入れで切り分け、両方を絞ると「公開は閉じ、プライベートだけ通す」閉域構成になることを体感する（Step1〜7 の「許可/経路/名前解決を出し入れして因果を確かめる」と同じ手法）

## Step9

`./step9`

1 つの公開エンドポイントの裏に複数のバックエンド VM を並べ、接続を分散する構成を学ぶ（PLAN の候補 B）
**Azure Load Balancer** を用いて L4（TCP/UDP）の負荷分散を行い、複数 VM をバックエンドプールにまとめ、ヘルスプローブで「生きている宛先」だけにトラフィックを振り分ける。
Nginx をインストールした 2 台の VM に対して `curl` でアクセスし、交互にレスポンスが返ってくること、および 1 台をダウンさせた場合に自動的に残りの 1 台へトラフィックが寄るフェイルオーバーの動作を確認する。

## Step10

`./step10`

Step9 の L4（IP・ポート）の分散に対し、HTTP の **URL パス**で振り分ける **L7（アプリケーション層）** のルーティングを学ぶ（PLAN の候補 C）
**Azure Application Gateway**（Standard_v2）を専用サブネットに置き、リバースプロキシとして「`/api/*` は API バックエンド（`vm-api`）へ、それ以外（`/`・`/web/`）は Web バックエンド（`vm-web`）へ」という URL パスマップで振り分ける。Nginx をパス問わず自分の役割（WEB/API）を返すよう設定した 2 台の VM に対し、同じ Public IP（同じ入口）でも **URL のパスだけで宛先が変わる**ことを `curl` で確認する。L4（Step9）では URL を変えても宛先が変わらなかったことと対比し、「何を見て振り分けているか」（5タプル vs HTTP の中身）の差分、専用サブネットの必要性、TLS 終端の概念を整理する

## Step11

`./step11`

各スポークが勝手に外へ出るのではなく、ハブの 1 か所（**Azure Firewall**）を必ず経由させ、許可した宛先（FQDN）だけ外へ出す「egress の中央集約と検査」を学ぶ（PLAN の候補 D）
ハブの専用サブネット `AzureFirewallSubnet`（予約名・/26 以上）に Azure Firewall（Standard）を置き、Firewall Policy のアプリケーションルールで `api.ipify.org`・`ifconfig.me` だけを許可する。スポーク `subnet-workload` の UDR で `0.0.0.0/0`（全外向き）を Firewall のプライベート IP に向け（強制トンネリング）、`defaultOutboundAccess: false` で他の出口を塞ぐ。パブリック IP を持たない `vm-workload` から `az vm run-command` で `curl` し、許可 FQDN へは出られて外から見た送信元が Firewall の公開 IP に集約（SNAT）されること、非許可 FQDN（`www.bing.com`）は遮断されることを確認する。`disable-route`/`enable-route` で `0.0.0.0/0` ルートを出し入れし、egress を成立させているのが「UDR → Firewall」の経路であることを切り分ける。Step3 の自前 NVA（無検査の素通し）・Step5 の NAT Gateway（無検査の SNAT 集約）との役割の違い（Firewall は集約＋検査・制御を兼ねる）を整理する

## Step12

`./step12`

Step1〜4 で ping や `ssh -J` を使って「通った／通らない」を都度たしかめてきた疎通を、**Network Watcher の診断と NSG フローログ**で体系的に観測する横断ステップを学ぶ（PLAN の候補 H）
最小環境（1 VNet・`subnet-app`・NSG `nsg-app`・パブリック IP なしの `vm-a`/`vm-b`・Network Watcher Agent 拡張）を作り、4 つの観測ツールを当てる。**IP Flow Verify** は実トラフィックを流さずに「この通信を NSG が許可/拒否するか・どのルールが効くか（access と ruleName）」を返し、VNet 内からの SSH は明示ルール `Allow-SSH-From-Vnet` で許可・Internet からの SSH は既定 `DefaultRule_DenyAllInBound` で拒否、という「許可は明示・拒否は既定」の構図を可視化する。**接続トラブルシュート**（`test-connectivity`）は `vm-a → vm-b:22` の到達可否と経路を実測し、**Next Hop** は宛先ごとの転送先（`VnetLocal`/`Internet`、UDR があれば `VirtualAppliance`）を判定として返す。**NSG フローログ**を Storage に有効化し、許可/拒否トラフィックを後から見返せるログとして記録する。仕上げに `lock`/`unlock`（SSH 許可より高優先度の Deny ルールを出し入れ）で、通信を 1 つも流さずに IP Flow Verify の判定が Allow⇄Deny と切り替わり“効いているルール名”まで変わることを観測し、Step1〜11 の「出し入れして因果を確かめる」手法を「体感（ping）」から「観測（診断・記録）」へ引き上げる