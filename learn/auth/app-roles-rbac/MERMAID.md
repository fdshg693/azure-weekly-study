# 認可フロー / 構成（mermaid）

`api-protect` との違いは、API がトークンを受け取ったあと **`roles` クレームでエンドポイント別の認可**を行う段が増えたこと。そして `roles` の出どころが「クライアントの要求」ではなく「**管理者によるユーザーへのロール割り当て**」である点。

## 全体フロー（認証 → 認可）

```mermaid
sequenceDiagram
    autonumber
    participant Admin as 管理者
    participant U as ユーザー
    participant SPA as SPA（クライアント:5173）
    participant IdP as Entra ID（IdP）
    participant API as 自前 API（リソースサーバー:3000）

    Admin->>IdP: ユーザーに App ロールを割り当て（task assign -- Tasks.Read など）
    Note over Admin,IdP: roles はクライアントが要求するのではなく<br/>管理者が主体に割り当てる

    U->>SPA: 「ログイン」
    SPA->>IdP: 認可要求（Auth Code + PKCE / openid profile）
    IdP-->>SPA: ID トークン（身分証）

    U->>SPA: 「タスク一覧を見る」/「追加」
    SPA->>IdP: アクセストークン要求（scope: api://<API>/access_as_user, forceRefresh）
    IdP-->>SPA: アクセストークン（scp=access_as_user, roles=[割り当て済みロール]）

    SPA->>API: GET/POST /api/tasks（Authorization: Bearer <token>）
    Note over API: 入口: 署名 / aud / scp を検証<br/>認可: roles に必要なロールがあるか
    alt 入口 NG（無効 / aud 違い）
        API-->>SPA: 401
    else scp 不足
        API-->>SPA: 403（アプリの許可が無い）
    else roles 不足
        API-->>SPA: 403（ユーザーの役割が無い）
    else すべて OK
        API-->>SPA: 200 / 201 + データ
    end
```

## scp と roles の出どころ（別レイヤー）

```mermaid
graph TD
    subgraph token["1 つのアクセストークン"]
      scp["scp = access_as_user<br/>（アプリの許可）"]
      roles["roles = [Tasks.Read, ...]<br/>（ユーザーの役割）"]
    end
    client["SPA が要求<br/>requiredResourceAccess + 同意"] --> scp
    admin["管理者が割り当て<br/>appRoleAssignment（ユーザー → API の SP）"] --> roles
```

## API の判定（api/server.js）

```mermaid
flowchart TD
    A[Authorization: Bearer token] --> B{Bearer がある?}
    B -- なし --> E401[401 Unauthorized]
    B -- あり --> C{署名・iss・aud・exp が正しい?}
    C -- いいえ --> E401
    C -- はい --> D{scp に access_as_user?}
    D -- なし --> E403s[403（アプリの許可不足）]
    D -- あり --> R{エンドポイントが要求する roles を持つ?}
    R -- /api/me（ロール不要） --> OK200[200 + scp/roles 表示]
    R -- Tasks.Read あり --> OKget[200 + 一覧]
    R -- Tasks.Write あり --> OKpost[201 + 追加]
    R -- 無し --> E403r[403（ユーザーの役割不足）]
```
