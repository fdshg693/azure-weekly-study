# 認証フロー / 構成（mermaid）

これまでとの違いは、**API が 2 段**になり、トークンが段ごとに**作り替えられて**伝わること。A が受け取るトークンは `aud=api://A`、B が受け入れるのは `aud=api://B`。その差を埋めるのが On-Behalf-Of(OBO) 交換。

## 全体フロー（SPA → 中間 API(A) → 下流 API(B)）

```mermaid
sequenceDiagram
    autonumber
    participant U as ユーザー / SPA(:5173)
    participant IdP as Entra ID（IdP）
    participant A as 中間 API(A)（:3000・confidential）
    participant B as 下流 API(B)（:3001）

    U->>IdP: ログイン＋A 宛トークン要求（scope=api://A/access_as_user）
    IdP-->>U: access_token（aud=api://A, name=ユーザー, scp=access_as_user）
    U->>A: GET /api/chain-obo（Authorization: Bearer <A 宛トークン>）
    A->>A: 受け取ったトークンを検証（署名/aud=api://A/scp）

    Note over A,IdP: ★OBO 交換：受け取ったトークンを assertion に、B 宛トークンを取りに行く
    A->>IdP: POST /token（grant_type=jwt-bearer, client_id=A, client_secret, assertion=<A 宛トークン>, scope=api://B/access_as_user, requested_token_use=on_behalf_of）
    IdP-->>A: access_token（aud=api://B, name=ユーザーのまま）

    A->>B: GET /api/downstream（Authorization: Bearer <B 宛トークン>）
    B->>B: 検証（署名/aud=api://B/scp）→ name はユーザー本人
    B-->>A: 200（ユーザーの身元つき応答）
    A-->>U: 200（B の応答を中継）
```

## naive 転送（失敗）↔ OBO 交換（成功）の対比

```mermaid
graph TD
    subgraph naive["chain-naive：生トークンをそのまま転送（失敗）"]
      n1["A が aud=api://A のトークンを受信"] --> n2["交換せず そのまま B へ転送"]
      n2 --> n3["B の audience 検証：aud が api://B でない"]
      n3 --> n4["401 Unauthorized ＝ aud 境界に阻まれる"]
    end
    subgraph obo["chain-obo：OBO 交換してから呼ぶ（成功）"]
      o1["A が aud=api://A のトークンを受信"] --> o2["OBO 交換：aud=api://B のトークンを取得（主体はユーザーのまま）"]
      o2 --> o3["B の audience 検証：aud=api://B で一致"]
      o3 --> o4["200 ＝ ユーザーとして B に到達（伝播成功）"]
    end
```

## トークンの aud と主体の変化（交換の前後）

```mermaid
graph LR
    subgraph before["A が受け取るトークン（交換前）"]
      b1["aud: api://A"]
      b2["scp: access_as_user"]
      b3["name/oid: ユーザー"]
    end
    subgraph after["OBO 交換後のトークン（B 宛）"]
      a1["aud: api://B  ← ここが変わる"]
      a2["scp: access_as_user"]
      a3["name/oid: ユーザーのまま  ← 変わらない"]
      a4["azp/appid: A（中間）"]
    end
    before -->|"OBO 交換（jwt-bearer / on_behalf_of）"| after
```

## 同意の置き場所の対比（委任 ↔ アプリ許可）

```mermaid
graph TD
    subgraph obo2["本プロジェクト：A→B は委任許可"]
      p1["oauth2PermissionGrant"] --> p2["clientId=A の SP / resourceId=B の SP / scope=access_as_user"]
      p2 --> p3["task consent / revoke-consent で出し入れ（無いと AADSTS65001）"]
    end
    subgraph ccd["client-credentials-daemon：アプリ許可"]
      q1["appRoleAssignment"] --> q2["principalId=デーモン SP / resourceId=API の SP / roles"]
      q2 --> q3["task grant / revoke で出し入れ"]
    end
```
