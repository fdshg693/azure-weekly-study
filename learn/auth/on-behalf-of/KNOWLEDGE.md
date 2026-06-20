# KNOWLEDGE — このプロジェクトで新たに出てくる用語・概念

`entra-spa-login` / `api-protect` / `app-roles-rbac` / `confidential-web` / `client-credentials-daemon` でカバー済みの語（OIDC、PKCE、ID/アクセストークン、JWT、リダイレクト URI、テナント、Authorization Code Flow、リソースサーバー、委任スコープ、JWKS、aud・scp・roles 検証、401・403、CORS、認証と認可、App ロール、クライアントシークレット、コンフィデンシャル／パブリッククライアント、SP、委任許可 vs アプリケーション許可、管理者同意、`.default`、idtyp 等）は繰り返さない。ここでは「**多段 API でのトークン引き継ぎ**」で登場する語に絞る。

## `aud` 境界（audience boundary）★このプロジェクトの起点

- アクセストークンには必ず **宛先（`aud`）** がある。`aud` は「このトークンは誰に向けて発行されたか」。
- リソースサーバーは自分宛（`aud` が自分）のトークンしか受け入れてはいけない（api-protect で検証した）。
- 帰結：**A が受け取った `aud=api://A` のトークンを、そのまま `aud=api://B` の B に転送しても通らない**（B が audience 検証で 401）。
- だから多段呼び出しでは「トークンをそのまま渡す」のではなく「**宛先を替えたトークンを取り直す**」必要がある。それが OBO。
- これは案1（api-protect）で `aud` を検証した理由の裏返し：宛先検証が効いているからこそ、宛先違いのトークンは弾かれ、交換が必要になる。

## On-Behalf-Of(OBO) フロー ★このプロジェクトの核心

- 「中間 API(A) が、サインインしたユーザーの代理で、下流 API(B) を呼ぶ」ためのトークン交換。
- A は **受け取ったユーザートークンを assertion（証拠）にして**、token エンドポイントに「これを B 宛トークンに替えて」と頼む。
- リクエスト（v2）：`POST /oauth2/v2.0/token`
  - `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer` … OBO（JWT ベアラー）の grant_type
  - `client_id` ＋ `client_secret` … A 自身の資格情報（**コンフィデンシャルクライアントでないと OBO できない**）
  - `assertion=<受け取ったユーザーアクセストークン>` … 「誰の代理か」の証拠
  - `scope=api://<B>/access_as_user` … 欲しい下流スコープ（委任なので個別スコープを指定できる。`.default` ではない）
  - `requested_token_use=on_behalf_of` … 「ユーザーの代理で」交換する宣言
- 返ってくるトークン：**`aud=api://B`** でありながら、**主体（`name`/`oid`）は元のユーザーのまま**。

## トークン交換（token exchange）と「アイデンティティ伝播」

- **トークン交換**：あるトークンを入力に、別の（宛先・スコープの違う）トークンを得る操作。OBO はその一種。
- **アイデンティティ伝播**：多段呼び出しで「最初にログインしたユーザーが誰か」を、段を越えて保ち続けること。
  - OBO で交換したトークンは主体がユーザーのまま ＝ B から見ても「ユーザーが呼んでいる」。`azp`/`appid` には中間の A が入り、「**A が、ユーザーとして**」という構図になる。
  - 対比：もし A が `client-credentials-daemon` のように「アプリ自身」として B を呼ぶと、B から見た主体は **A（アプリ）** になりユーザーは消える。OBO は「ユーザーを消さずに」段をまたぐための仕組み。

## client credentials との対比（ユーザーを保つか/消すか）

| | OBO（本プロジェクト） | client credentials（案4） |
|---|---|---|
| 出発点 | ユーザーがログイン済み（A がそのトークンを保持） | ユーザー不在 |
| grant_type | `urn:...:jwt-bearer` | `client_credentials` |
| assertion | あり（ユーザートークン） | なし |
| scope | 個別スコープ可（`api://B/access_as_user`） | `.default` 固定 |
| 下流トークンの主体 | **元のユーザー**（name/oid あり、scp あり） | アプリ（roles のみ、name/scp なし、idtyp=app） |
| 同意の形 | A→B の**委任**許可（`oauth2PermissionGrant`） | アプリへの**アプリケーション**許可（`appRoleAssignment`） |

- どちらも「中間のサーバーが、その先の API を呼ぶ」点は同じ。違いは **ユーザーの身元を伝播するか（OBO）／アプリとして動くか（client credentials）**。

## 中間層の委任同意（A→B の `oauth2PermissionGrant`）

- OBO は「A がユーザーの代理で B を呼ぶ」ので、**A→B の委任許可への同意**が前提。これが無いと交換は **AADSTS65001（要同意）** で失敗する。
- 同意の実体は **`oauth2PermissionGrant`**（clientId=A の SP、resourceId=B の SP、scope=`access_as_user`、consentType=AllPrincipals＝管理者同意）。
- `client-credentials-daemon` の同意は `appRoleAssignment`（アプリ許可）だった。**委任なら `oauth2PermissionGrant`、アプリ許可なら `appRoleAssignment`**。同じ「管理者同意」でも置き場所（Graph のオブジェクト）が違う。
- 本プロジェクトの `task consent`/`task revoke-consent` がこの出し入れ。取り消すと chain-obo が 502 に戻る。

## 多段構成での「各段は次の段だけ知る」

- SPA は A のスコープ（`api://A/access_as_user`）だけを要求し、B を知らない。
- A は B のスコープ（`api://B/access_as_user`）を OBO で要求し、SPA のことは「呼ばれる側」として受けるだけ。
- このように各段は**自分の次の段**だけを知り、トークンは段ごとに**作り替えられて**伝わる。1 本のトークンが全段を貫くのではない、という多段設計の基本。
