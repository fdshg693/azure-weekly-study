# 認証フロー / 構成（mermaid）

`entra-spa-login` との違いは、**ユーザーも認可コードもリダイレクトも無く、アプリ自身がシークレットだけでトークンを取る**こと。届くトークンには `scp`・`name` が無く `roles` だけがある。

## 全体フロー（Client Credentials Flow）

```mermaid
sequenceDiagram
    autonumber
    participant D as デーモン（バッチ / クライアント）
    participant IdP as Entra ID（IdP）
    participant API as 自前 API（リソースサーバー:3000）

    Note over D: 人間はいない。アプリ自身の資格情報だけ。
    D->>IdP: POST /token（grant_type=client_credentials, client_id, client_secret, scope=api://<API>/.default）
    Note over IdP: 認可コードもログイン画面も無い直接通信
    IdP-->>D: access_token（roles=Tasks.Process.All / scp・name は無し / idtyp=app）

    D->>API: GET /api/tasks（Authorization: Bearer <token>）
    API->>API: 署名(JWKS) / aud / roles を検証（scp は見ない）
    API-->>D: 200（roles あり）/ 403（roles 無し＝未付与）
```

## 委任（これまで）↔ アプリケーション許可（本プロジェクト）の対比

```mermaid
graph TD
    subgraph deleg["委任許可（entra-spa-login / app-roles-rbac）"]
      u1["ユーザーがサインイン"] --> u2["ユーザーがその場で同意（または代表同意）"]
      u2 --> u3["トークンに scp ＋ name（ユーザーの代理）"]
      u3 --> u4["ロールは『ユーザー』に割り当て"]
    end
    subgraph appperm["アプリケーション許可（本プロジェクト）"]
      a1["ユーザー不在・アプリ自身"] --> a2["管理者が事前にアプリへ付与（管理者同意）"]
      a2 --> a3["トークンに roles のみ（name・scp 無し / idtyp=app）"]
      a3 --> a4["ロールは『アプリの SP』に割り当て"]
    end
```

## トークンの中身の違い（誰として動いているか）

```mermaid
graph LR
    subgraph spa["SPA のアクセストークン（委任）"]
      s1["aud: api://<API>"]
      s2["scp: access_as_user"]
      s3["name / preferred_username: ユーザー"]
      s4["sub/oid: ユーザーの ID"]
    end
    subgraph dae["デーモンのアクセストークン（アプリ許可）"]
      d1["aud: api://<API>"]
      d2["roles: Tasks.Process.All"]
      d3["idtyp: app（name・scp は無し）"]
      d4["sub/oid: デーモンの SP の ID"]
    end
```

## どこに何が在るか（資格情報の所在）

```mermaid
graph LR
    subgraph secret[".env（サーバー/デーモンのみ・gitignore）"]
      cs["CLIENT_SECRET（デーモンの資格情報）"]
    end
    subgraph entra["Entra ID"]
      grant["デーモン SP への appRoleAssignment<br/>= Tasks.Process.All の付与（grant/revoke で出し入れ）"]
    end
    cs -->|"token 要求（client credentials）"| entra
    grant -->|"付与済みなら roles に乗る"| token["access_token（roles）"]
    token -->|"Bearer で API へ"| api["自前 API（roles を検証）"]
```
