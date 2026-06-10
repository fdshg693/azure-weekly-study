# KNOWLEDGE.md (advanced/step1)

このステップで新たに登場した用語や概念を解説します。
（Application Gateway・リスナー・リバースプロキシ・バックエンド HTTP 設定など L7 の基礎は basic/step10 を参照）

## WAF（Web Application Firewall）
HTTP/HTTPS の**中身**（URL・クエリ・ヘッダ・ボディ）を検査し、既知の攻撃パターンに一致するリクエストを検知・遮断する仕組みです。
ネットワーク層（IP/ポート）を見る NSG や、L4 で振り分ける Load Balancer とは違い、**アプリケーション層の攻撃**（SQL インジェクション、クロスサイトスクリプティング等）を対象にします。
L7 リバースプロキシ（Application Gateway）は HTTP の中身を読める位置にいるため、そこに WAF を載せるのが自然です。

## OWASP マネージドルールセット（CRS: Core Rule Set）
WAF が照合する「攻撃パターンの辞書」です。OWASP（Open Worldwide Application Security Project）が公開する CRS をベースに、
SQLi・XSS・LFI/RFI・プロトコル違反など Top 10 系の攻撃を検出するルール群がまとめられています。
本ステップでは `OWASP 3.2` を使用します。個別ルールは必要に応じて除外（false positive 対策）できますが、本ステップでは既定のまま使います。

## WAF の動作モード（Detection / Prevention）
WAF ポリシーの中心スイッチです。**同じ検出ロジックでも、一致したときの「振る舞い」が変わります**。

| モード | 一致時の動作 | 用途 |
| --- | --- | --- |
| **Detection（検知）** | **ブロックしない**。ログに記録するだけで、リクエストはバックエンドへ通る | 導入初期の様子見・誤検知の洗い出し |
| **Prevention（防御）** | **実ブロック**（HTTP 403 を返す）。リクエストはバックエンドへ届かない | 本番の防御 |

新しいルールをいきなり Prevention で有効にすると正常な通信まで弾く恐れがあるため、
まず Detection でログを観察し、誤検知が無いと確認してから Prevention へ上げる、という運用が定石です。
本ステップではこの 2 モードを出し入れし、`403 ⇄ 200` の差として体感します。

## TLS 終端（TLS Termination）— 今回は「実装」
basic/step10 では概念として整理しただけでしたが、本ステップでは実際に行います。
クライアントとの間で HTTPS を**復号**することを TLS 終端と呼びます。復号して平文の HTTP になって初めて、WAF が中身を検査でき、L7 ルーティングも成立します。
復号後にバックエンドへどう送るかで 2 方式あります。

- **TLS オフロード**：復号した後、バックエンドへは HTTP で送る（本ステップはこちら。`backend-pool` へ HTTP/80）。
- **エンドツーエンド TLS**：バックエンドへ再暗号化して HTTPS で送る。

## SSL 証明書とリスナーへの紐付け
HTTPS リスナーは、フロントエンドのポート 443 で待ち受け、**SSL 証明書**を使って TLS 終端します。
Application Gateway では証明書を `sslCertificates`（PFX 形式の証明書データ＋パスワード）として登録し、リスナーから参照します。

- **自己署名証明書**：本ステップで使用。CA の署名がないため、ブラウザ/`curl` は「信頼できない」と警告します（`curl -k` で検証をスキップ）。**学習用途のみ**。
- **本番の証明書運用**：公的 CA（または社内 CA）が署名した証明書を使い、**Azure Key Vault** に格納して Application Gateway から参照するのが定石です（証明書の更新・秘密鍵の保護・アクセス制御を一元化できる）。本ステップでは構成を単純にするため Key Vault は使わず、`just` が生成した PFX を直接デプロイ時に渡しています。

## WAF_v2 SKU
Application Gateway の SKU の 1 つ。basic/step10 の `Standard_v2` に WAF 機能を加えたものです。
WAF ポリシー（`ApplicationGatewayWebApplicationFirewallPolicies`）を**ゲートウェイ全体**（またはリスナー/パス単位）に関連付けて使います。
新しい構成では、ゲートウェイ内に WAF 設定を直書きする旧方式ではなく、**独立した WAF ポリシーリソースを関連付ける**方式が推奨されます（ポリシーを複数ゲートウェイで共有・再利用しやすい）。

## 診断設定と WAF ログ
Application Gateway の**診断設定**で、ログを Log Analytics 等へ送れます。本ステップで使う主なカテゴリは次の 2 つです。

- **ApplicationGatewayFirewallLog**：WAF が何を検知し、どう処理したか（`action`=Matched/Blocked、一致した `ruleId`、対象 URI 等）。Detection モードで「ブロックせずログだけ残る」ことを確認するのに使います。
- **ApplicationGatewayAccessLog**：通常のアクセスログ（誰がどの URL にアクセスし、何のステータスを返したか）。

ログは Log Analytics の `AzureDiagnostics` テーブルに入り、KQL で検索できます（反映まで数分のラグがあります）。

## ingress の検査 vs egress の検査（basic/step11 との対比）
- basic/step11（Azure Firewall）は、内部から**外へ出る**通信を宛先 FQDN で検査・制御する「**外向き(egress)** の検査」でした。
- 本ステップの WAF は、外から**入ってくる**リクエストの中身を検査・遮断する「**内向き(ingress)** の検査」です。

「検査をどこで・どの向きに行うか」という観点で、両者は対になる関係にあります。
