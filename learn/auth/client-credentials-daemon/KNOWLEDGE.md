# KNOWLEDGE — このプロジェクトで新たに出てくる用語・概念

`entra-spa-login` / `api-protect` / `app-roles-rbac` / `confidential-web` でカバー済みの語（OIDC、PKCE、ID/アクセストークン、JWT、リダイレクト URI、テナント、Authorization Code Flow、リソースサーバー、委任スコープ、JWKS、aud・scp・roles 検証、401・403、CORS、認証と認可、App ロール、クライアントシークレット、コンフィデンシャル／パブリッククライアント、SP 等）は繰り返さない。ここでは「**ユーザーのいない認証**」で登場する語に絞る。

## Client Credentials Flow ★このプロジェクトの核心

- **ユーザーがいないフロー**。アプリ自身の資格情報（クライアントシークレット／証明書）だけで、token エンドポイントから直接アクセストークンを取る。
- リクエストは `POST /oauth2/v2.0/token` に `grant_type=client_credentials` ＋ `client_id` ＋ `client_secret` ＋ `scope`。**認可コードも、リダイレクトも、ユーザーの同意画面も無い**。
- 用途：バッチ、夜間ジョブ、常駐デーモン、サービス間通信、CI/CD など「人間が対話しない」処理。
- 必ず**コンフィデンシャルクライアント**（秘密を安全に持てる）でしか使えない。パブリッククライアント（SPA）は秘密を持てないので不可。

## 委任許可（delegated）vs アプリケーション許可（application）★最重要の対比

| | 委任許可（delegated） | アプリケーション許可（application） |
|---|---|---|
| 主体 | サインインした**ユーザーの代理**としてアプリが動く | **アプリそのもの**が動く（ユーザー不在） |
| 同意 | **ユーザーがその場で同意**（または管理者が代表同意） | **管理者が事前にアプリへ付与**（管理者同意） |
| トークンのクレーム | `scp`（要求したスコープ）＋ユーザークレーム（`name` 等） | `roles`（付与されたアプリ許可）。ユーザークレームは無い |
| Entra の登録 | App ロール `allowedMemberTypes=User` / Expose an API のスコープ | App ロール `allowedMemberTypes=Application` |
| `requiredResourceAccess` の type | `Scope` | `Role` |
| 割り当て先 | **ユーザー**（または管理者の代表同意） | **アプリの SP** |
| これまでの auth | entra-spa-login / api-protect / app-roles-rbac / confidential-web | **本プロジェクト** |

- ひとことで言えば「**ユーザーの代理か、アプリそのものか**」。`app-roles-rbac` で「ユーザーに」ロールを割り当てたのと同じ構造を、「アプリに」割り当てるのがアプリケーション許可。
- 重要な含意：アプリケーション許可は**ユーザーの権限に縛られない**ので強力。だから付与には**管理者**が要り、最小権限で絞るべき。

## 管理者同意（admin consent）

- 委任スコープはユーザー自身が同意できることが多い（`entra-spa-login` の dynamic consent）。
- **アプリケーション許可はユーザーが同意できない**。テナントの管理者が「このアプリにこの許可を与える」と決める＝管理者同意。
- 本プロジェクトでは、デーモンの SP に App ロールを割り当てる操作（`task grant`）がこれに当たる（`appRoleAssignments` への POST）。取り消し（`task revoke`）は DELETE。

## `.default` スコープ

- client credentials では `scope` に個別の権限名を並べられない。必ず **`<リソース>/.default`**（例 `api://<API_CLIENT_ID>/.default`）を使う。
- 意味：「このアプリに（管理者同意で）**静的に与えられた**、このリソース宛の許可をすべて」。
- 委任フロー（SPA）は `access_as_user` のように**動的に**個別スコープを要求できた。それは「ユーザーがその場で同意する」前提だから。client credentials は「事前に管理者が与えた許可」で動くので、その場の選り好み（動的要求）が無く `.default` 固定になる。

## `idtyp` クレームと「ユーザー不在」の見分け方

- アプリケーション許可で取ったトークンには **`idtyp=app`**（識別子の型＝アプリ）が乗ることがある。
- ユーザー由来のクレーム（`name` / `preferred_username` / `scp`）は**無い**。`sub` / `oid` は呼び出し元アプリの**サービス プリンシパルの ID** になる（人の ID ではない）。
- `azp` / `appid` に呼び出し元アプリ（デーモン）の clientId が入る。
- これらを `entra-spa-login` のトークン（`name` あり・`scp` あり）と並べて見ると、「誰として動いているか」の違いが一目で分かる。

## クライアントシークレットの「重荷」と、この先の脱却

- 本プロジェクトのデーモンは**シークレット**で動く。だが秘密は「管理・漏洩・ローテーション」のコストがつきまとう。
- これを **消す**のが後続：
  - 案7 **managed-identity**：Azure 上のリソースなら資格情報を Azure に持たせてシークレットを消せる（Azure 内のシークレットレス）。
  - 案8 **workload-identity-federation**：Azure の外（CI/CD・他クラウド）からも、外部 IdP の信頼でシークレットなしに認証する。
- つまり本プロジェクトは「シークレットで動くデーモン」の出発点で、この先は同じ client credentials 的な動きを**シークレットなし**に置き換えていく。
