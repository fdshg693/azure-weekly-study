# 認証フロー / 構成（mermaid）

`entra-spa-login` との違いは、**トークン交換をサーバーがクライアントシークレット付きで行い、トークンをブラウザに渡さない**こと。ブラウザが持つのは `sid` クッキーだけ（BFF）。

## 全体フロー（認可コードフローをサーバーで完結）

```mermaid
sequenceDiagram
    autonumber
    participant B as ブラウザ
    participant S as 自分のサーバー（Web アプリ:3000）
    participant IdP as Entra ID（IdP）
    participant G as Microsoft Graph

    B->>S: GET /login
    S->>S: state / nonce を発番（pending に保存）
    S-->>B: 302 → Entra authorize（code 要求, state, nonce）
    B->>IdP: authorize（ログイン＋同意）
    IdP-->>B: 302 → /auth/callback?code=...&state=...
    B->>S: GET /auth/callback（code, state）

    Note over S,IdP: ★ ここがコンフィデンシャルの肝
    S->>IdP: POST /token（code + client_secret）★ ブラウザを介さない直接通信
    IdP-->>S: id_token / access_token / refresh_token

    S->>S: id_token を検証（署名/iss/aud/nonce）→ セッション作成（トークンはサーバー保持）
    S-->>B: 302 → /（Set-Cookie sid=… / HttpOnly）

    Note over B: ブラウザが持つのは sid クッキーだけ。トークンは無い。
    B->>S: GET /api/graph（cookie: sid を自動送信）
    S->>G: GET /me（Authorization: Bearer <サーバー保持のaccess_token>）
    G-->>S: ユーザー情報
    S-->>B: 結果（JSON）だけ返す（トークンは渡さない）
```

## パブリック（SPA）↔ コンフィデンシャル（Web）の対比

```mermaid
graph TD
    subgraph pub["パブリッククライアント（これまでの SPA）"]
      p1["秘密を持てない"] --> p2["PKCE でコード横取りを防ぐ"]
      p2 --> p3["トークンはブラウザ（sessionStorage）"]
    end
    subgraph conf["コンフィデンシャルクライアント（本プロジェクト）"]
      c1["秘密を持てる（client_secret）"] --> c2["token 交換をサーバーがシークレット付きで実行"]
      c2 --> c3["トークンはサーバー保持／ブラウザは sid クッキーだけ（BFF）"]
    end
```

## どこに何が在るか（トークンの所在）

```mermaid
graph LR
    subgraph browser["ブラウザ"]
      sid["sid クッキー（httpOnly）<br/>※トークンは無い"]
    end
    subgraph srv["自分のサーバー（メモリ）"]
      sess["セッション: sid → {id/access/refresh トークン}"]
    end
    subgraph secret[".env（サーバーのみ・gitignore）"]
      cs["CLIENT_SECRET"]
    end
    sid -->|"同一オリジンで自動送信"| sess
    cs -->|"token 交換／リフレッシュで使用"| sess
```
