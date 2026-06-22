# MERMAID — 構成とフロー V2.0

V1 の構成図・メッセージ陳腐化フローは `versions/v1/MERMAID.md` を参照。
ここでは **V2 で追加する認証・友達リストのフロー** を示す。

## コンポーネント構成（V2・ACS と JWT 検証を追加）

```mermaid
flowchart LR
  Browser["ブラウザ<br/>JWT を localStorage 保持<br/>Authorization: Bearer"]
  BFF["BFF (Express)<br/>**JWT 検証** → X-User 注入"]
  API["読み取り API (FastAPI)<br/>login(JWT発行) / friends一覧 / 会話"]
  FUNC["書き込み (Functions)<br/>signup / verify / friends追加削除 / 送信"]
  ACS["ACS Email<br/>検証メール送信"]
  COSMOS[("Cosmos DB<br/>users / messages / friends")]
  REDIS[("Redis<br/>会話 / friends キャッシュ")]

  Browser -- "静的配信 + /api/*（Bearer）" --> BFF
  BFF -- "検証済み X-User で読み取り" --> API
  BFF -- "検証済み X-User で書き込み" --> FUNC
  BFF -. "login / verify は検証前(例外)" .-> API
  FUNC -- "検証メール（acs時）" --> ACS
  API -- "read-through" --> REDIS
  FUNC -- "append / upsert" --> COSMOS
  API -- "miss 時" --> COSMOS
```

## サインアップ → メール検証 → ログイン

```mermaid
sequenceDiagram
  participant U as ユーザー
  participant BFF
  participant FUNC as Functions
  participant API as FastAPI
  participant ACS as ACS Email
  participant COSMOS as Cosmos

  U->>BFF: POST /api/signup {email, username, password}
  BFF->>FUNC: 転送（トークン不要）
  FUNC->>COSMOS: users upsert（passwordHash / emailVerified=false / verifyToken）
  alt EMAIL_MODE=acs
    FUNC->>ACS: 検証リンク付きメールを送信
    ACS-->>U: メール受信
  else EMAIL_MODE=local
    FUNC-->>U: リンクをコンソール/.verify-links に出力
  end

  U->>BFF: GET /api/verify?token=...（メールのリンク）
  BFF->>FUNC: 転送
  FUNC->>COSMOS: token 照合 → emailVerified=true / token 失効
  FUNC-->>U: 検証完了

  U->>BFF: POST /api/login {email, password}
  BFF->>API: 転送
  API->>COSMOS: email でユーザー取得（クロスパーティション）
  API->>API: passwordHash 検証 + emailVerified 確認
  API-->>U: 200 + JWT（未検証なら 403）
```

## 認証済みリクエスト（BFF が信頼境界）

```mermaid
sequenceDiagram
  participant Browser
  participant BFF
  participant API as FastAPI / Functions

  Browser->>BFF: GET /api/friends（Authorization: Bearer <JWT>）
  alt JWT が有効
    BFF->>BFF: 署名 / exp を検証 → sub=username 取得
    BFF->>API: 転送（X-User: <username> を注入）
    API-->>Browser: 200 データ
  else 無効 / 改ざん / 失効
    BFF-->>Browser: 401（下流へ流さない）
  end
```

## 友達追加（自己完結：自分の操作 = 自分のキャッシュのみ）

```mermaid
sequenceDiagram
  participant A as alice
  participant BFF
  participant FUNC as Functions
  participant API as FastAPI
  participant COSMOS as Cosmos
  participant REDIS as Redis

  A->>BFF: POST /api/friends {username: bob}（Bearer）
  BFF->>FUNC: 転送（X-User: alice）
  FUNC->>COSMOS: friends upsert（id=alice__bob, owner=alice）
  Note over FUNC,REDIS: bob のリストには何も作らない（一方向）
  FUNC->>REDIS: friends:alice を削除（自分の操作 → 自分のキャッシュ）
  FUNC-->>A: 201

  Note over A: 直後にリスト取得
  A->>BFF: GET /api/friends
  BFF->>API: 転送（X-User: alice）
  Note over REDIS: friends:alice は miss → Cosmos から再構築
  API-->>A: bob を含む最新リスト（即時反映・陳腐化なし）
```
