# KNOWLEDGE — workload-identity で新たに出た用語・概念

`simple` / `config-rollout` でカバー済みの語（Deployment / Service / Ingress / Secret /
ConfigMap / namespace / probe など）は繰り返さない。このプロジェクトで**新しく主役になった**ものだけ書く。

## Workload Identity（AKS の）
Pod が、k8s の ServiceAccount トークンを **Microsoft Entra のトークンに交換**して Azure リソースへ
アクセスできるようにする仕組み。Pod 側にシークレット（クライアントシークレットや接続文字列）を
置かずに済む＝**キーレス**。旧来の AAD Pod Identity の後継で、OIDC フェデレーションを使う。

有効化に必要な 2 つ（`az aks update`）:
- `--enable-oidc-issuer`: クラスタが **OIDC issuer**（トークンの発行元 URL）を公開する。
- `--enable-workload-identity`: **mutating webhook** を入れ、対象 Pod にトークン交換用の env と  projected volume を自動注入する。

## OIDC issuer（の URL）
AKS が公開する「このクラスタが発行する SA トークンの発行元」を表す URL。
Entra 側はこの URL を信頼の起点として、トークンの真正性を検証する。
`az aks show --query oidcIssuerProfile.issuerUrl` で取得できる。

## User-Assigned Managed Identity（UAMI）
Azure 側に独立して作る「ユーザー割り当てマネージド ID」。ライフサイクルが特定リソースから独立し、
複数リソースで共有・付け替えできる（`simple` の AKS は System-Assigned だった点と対比）。
本プロジェクトでは Pod が「なりすます」相手で、PostgreSQL のログインユーザー名にもなる。
重要な属性: `clientId`（SA 注釈に入れる）と `principalId`（PG の Entra 管理者登録に使う）。

## Federated Identity Credential（FIC）
UAMI に付ける「どの外部 IdP の、どの主体（subject）を信頼してトークン交換を許すか」の設定。
- `issuer`: AKS の OIDC issuer URL。
- `subject`: `system:serviceaccount:<namespace>:<serviceaccount>`。**この SA だけ**を信頼する。
- `audiences`: `api://AzureADTokenExchange`（Entra のトークン交換用に固定）。

この 3 つが、k8s の SA と Azure の UAMI を**パスワードなしで結ぶ鍵**。

## ServiceAccount への紐付け（k8s 側）
- `metadata.annotations` の `azure.workload.identity/client-id`: なりすます UAMI の clientId。
- Pod テンプレートの `labels` の `azure.workload.identity/use: "true"`: このラベルが無いと
  webhook は env を注入しない（＝交換が起きない）。

webhook が Pod に注入する主な env:
`AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_AUTHORITY_HOST` / `AZURE_FEDERATED_TOKEN_FILE`
（最後は SA トークンが書かれた projected volume のパス）。`DefaultAzureCredential` はこれらを
検出して `WorkloadIdentityCredential` として動く。

## PostgreSQL Flexible Server の Microsoft Entra 認証
パスワードの代わりに **Entra のアクセストークン**でログインする方式。
- 有効化: `az postgres flexible-server update --active-directory-auth Enabled`
  （`--password-auth Enabled` を併用すれば従来のパスワード接続も共存できる）。
- ログイン: ユーザー名 = Entra プリンシパル名（本プロジェクトでは UAMI 名）、
  パスワード = スコープ `https://ossrdbms-aad.database.windows.net/.default` のアクセストークン。
- 権限付与: `az postgres flexible-server ad-admin create`（`--type ServicePrincipal`）で Entra 管理者として登録すると、そのプリンシパルが DB にログインできるようになる。

## 認証（AuthN）と認可（AuthZ）の分離
本プロジェクトの実験 A が示すこと: **トークンを取得できる（認証成立）こと**と、
**DB がログインを許す（認可成立）こと**は別。ロールを外すとトークンは取れるのに拒否される。
auth トピックで学んだ「ロール／クレームで挙動が変わる」を k8s + DB に持ち込んだ橋渡し。
