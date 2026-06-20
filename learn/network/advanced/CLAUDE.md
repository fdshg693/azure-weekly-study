# Azure を通じてネットワークを学習（advanced）

`basic`（step1〜12）で築いた基礎の上に、basic がスコープ外として切った発展領域（ハイブリッド接続・動的ルーティング・広域設計・セキュリティの作り込み・コンテナ／PaaS 固有のネットワーク・観測の運用化）へ踏み込む学習群。
方針は basic と同じ ―― 「まず一般概念 → Azure 実装」「設定を出し入れして、通信の変化から因果を確かめる」。ただし basic と違い **1 ステップ＝1 概念にこだわらず**、関連する複数概念を 1 ステップにまとめてよい。

## ルート直下ファイル

- `README.md`：このフェーズで何を・どう学ぶか、進め方、実装済みステップの一覧
- `PLAN.md`：次のステップ候補（案1〜8）・レベル・関連 basic ステップ・進め方のグループ分け
- `CLAUDE.md`（このファイル）

## 各ステップ共通ファイル構成

basic と同じだが、構成が大きくなるため Bicep は `modules/` 配下に役割分割する点が違う。

- `justfile`
    - just コマンドで利用するファイル。Azure でのネットワーク構築や通信確認などのコマンドをまとめる

- `KNOWLEDGE.md`
    - このステップで新たに出てきた用語・概念をまとめる。前のステップ（basic 含む）でカバーした内容は含めない

- `README.md`
    - このステップで行う内容の説明や、学習の流れを記載する

- `MERMAID.md`
    - ネットワーク構成を mermaid 形式で表現する。シナリオ単位で図をかき分けて理解促進を図る

- `main.bicep` ＋ `modules/*.bicep`
    - `main.bicep` はオーケストレータに徹し、各責務を `modules/` 配下へ分割する
    - 分ければよいというものではなく、可読性・理解のしやすさを最優先に分割粒度を決める

## ステップ一覧

### Step1

`./step1`（PLAN の案4）

L7 リバースプロキシを「振り分ける場所」から「**通す前に中身を検査して防ぐ場所**」へ引き上げる構成を学ぶ（basic/step10 の発展）。
**Application Gateway を WAF_v2 SKU** で構成し、**WAF ポリシー**（OWASP 3.2 マネージドルールセット）を関連付けて、復号後の HTTP の中身を SQLi/XSS など Top 10 系の攻撃パターンと照合する。リスナーを **HTTPS(443)** にして**自己署名証明書で TLS 終端**し（バックエンドへは HTTP/80 でオフロード）、復号して初めて中身を検査できることを体感する。WAF ポリシーの `mode` を **Detection（検知＝ログのみ）⇄ Prevention（防御＝実ブロック）** で出し入れし、同じ悪性リクエスト（`?id=1' OR '1'='1`）が `200`（バックエンド到達）⇄ `403`（手前で遮断）と変わることで、止めているのが WAF の mode であることを切り分ける。診断設定で WAF ログを Log Analytics に送り、Detection でも「ログだけは残る」ことを確認する。basic/step11（Azure Firewall の FQDN egress 制御）が「外向きの検査」だったのに対し、本ステップは「内向きの検査」と対比する

### Step2

`./step2`（PLAN の案5）

受け口を **リージョン内** から **グローバルなエッジ（ユーザーに近い場所）** へ引き上げ、そこで**体積型攻撃を緩和**し、**オリジンへの直アクセスを塞ぐ**「入口の作り込み」を学ぶ（basic/step9・10、advanced/step1 の発展）。
**Azure Front Door（Standard）** をエニーキャストの L7 エッジ入口として置き、オリジン（Nginx VM の公開 FQDN）へ HTTP で転送する。Front Door の **WAF ポリシーにレート制限ルール（30 req / 1 分 / クライアント IP）** を載せ、`just flood` で短時間に大量リクエストを送ると、`mode` が **Prevention** なら閾値超過分が `429`（Too Many Requests）で弾かれ、**Detection** なら同じバーストでも全て `200`（ログのみ）になることを観測して、体積型攻撃の緩和を体感する。さらにオリジンの NSG で送信元を service tag **`AzureFrontDoor.Backend`** だけに限定し、`lock-origin`/`unlock-origin` の出し入れで「オリジンへの直アクセスは塞がれ、必ずエッジを通る（エッジ・フロンティング）」ことを切り分ける。**有償の DDoS Protection プランはデプロイせず概念のみ**とし、L3/L4 の体積型は「Azure 基盤の常時 DDoS 防御＋必要に応じて有償プランで強化」という整理に留める。basic/step9・10 の「リージョン内の分散」、advanced/step1 の「リージョン内の WAF」と対比し、Front Door（エッジ）→ App Gateway（リージョン WAF）→ バックエンド と重ねれば多層の入口防御になることを整理する

### Step3

`./step3`（PLAN の案1）

**物理的に離れた拠点同士を公衆網越しの暗号化トンネルでつなぎ、BGP で経路を自動交換する**ハイブリッド接続の中核を学ぶ（basic/step2 のピアリング・basic/step3 の静的 UDR の発展）。検証用の "オンプレ" は別 VNet ＋ 別 VPN Gateway で代用し、`vnet-hub`(10.0.0.0/16) と `vnet-onprem`(10.50.0.0/16) の各 `GatewaySubnet` に **VPN Gateway（VpnGw1 / RouteBased / BGP 有効）** を置いて **VNet-to-VNet（IPsec/IKE・事前共有鍵）** で双方向に結ぶ。両ゲートウェイに**異なる ASN**（hub=65515 / onprem=65501）を割り当て、トンネル上で **BGP セッション**を張る。疎通は各拠点のテスト VM（Nginx・公開 IP なし）に対し **`az vm run-command`** で VM の内側から対向 private IP へ curl して確認する（トンネル経由の private 通信だけを純粋に見る）。出し入れは 2 つ ―― ① **トンネル up/down**（接続を削除/再作成）で `test` の 200⇄TIMEOUT と `learned-routes` の経路出現/消失が連動し、到達を支えているのが「トンネル＋経路交換」だと切り分ける。② **`add-prefix`** で onprem VNet に `10.60.0.0/16` を足すと、**経路を一切手書きしないのに** hub の `learned-routes` に `origin=EBgp` で自動的に現れる ―― **静的 UDR（手作業が必要）との決定的な対比＝BGP の真価**を体感する。`list-learned-routes`／`list-bgp-peer-status` で動的ルーティングを観測。**VPN Gateway 2 台はプロビジョニング 30〜45 分・時間課金が高く、検証後の `just cleanup` 必須**を明記。本物のオンプレ相手なら Local Network Gateway ＋ `connectionType: IPsec` を使う点、ポリシーベース（BGP 不可）との違いも整理。Site-to-Site の本番運用（ExpressRoute・active-active 冗長・カスタム IPsec ポリシー）は未着手
