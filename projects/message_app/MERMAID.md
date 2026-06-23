# MERMAID — 構成とフロー V3.0

V1（構成図・メッセージ陳腐化フロー）は `versions/v1/MERMAID.md`、
V2（認証・友達リストのフロー）は `versions/v2/MERMAID.md` を参照。
ここでは **V3 で変わる「知り合い／友達の二段階関係」「友達ゲート送信」「双方向キャッシュ無効化」** を示す。
コンポーネント構成は V2 から不変（新サービスなし）なので再掲しない。

## 関係の状態遷移（知り合い → 友達）

```mermaid
stateDiagram-v2
  [*] --> 無関係
  無関係 --> 片方向: A が B を知り合い登録 (A→B)
  片方向 --> 友達: B も A を知り合い登録 (B→A)（相互マッチ）
  友達 --> 片方向: どちらかが知り合い解除
  片方向 --> 無関係: 残りの片方向も解除
  note right of 片方向
    A→B のみ。B から見ると inbound。
    メッセージは送れない（403）。
  end note
  note right of 友達
    A→B かつ B→A。
    メッセージ送受信できる。
  end note
```

## 知り合い追加と「他人のキャッシュ」無効化（V3 の肝）

V2 と違い、A の操作は **B 側のキャッシュ**（inbound・相互成立時は友達）にも影響する。

```mermaid
sequenceDiagram
  participant A as alice
  participant BFF
  participant FUNC as Functions
  participant COSMOS as Cosmos(acquaintances)
  participant REDIS as Redis

  A->>BFF: POST /api/acquaintances {username: bob}（Bearer）
  BFF->>FUNC: 転送（X-User: alice）
  FUNC->>COSMOS: dual-write: out__alice__bob(pk=alice) と in__bob__alice(pk=bob) を upsert
  FUNC->>COSMOS: in__alice__bob(pk=alice) は存在？（= bob→alice のミラー。単一パーティション）
  FUNC->>REDIS: acq:alice 無効化（alice の知り合いが増えた）
  FUNC->>REDIS: acqby:bob 無効化（bob の inbound が増えた）
  alt bob→alice が既にある（相互マッチ成立）
    FUNC->>REDIS: friends:alice と friends:bob を無効化
    Note over FUNC,REDIS: A の操作が B のキャッシュにも及ぶ＝V2 では無かった構図
  end
  FUNC-->>A: 201
```

## 友達ゲート付きメッセージ送信＋双方向キャッシュ無効化

```mermaid
sequenceDiagram
  participant A as alice
  participant BFF
  participant FUNC as Functions
  participant COSMOS as Cosmos
  participant REDIS as Redis

  A->>BFF: POST /api/messages {to: bob, text}（Bearer）
  BFF->>FUNC: 転送（X-User: alice）
  FUNC->>COSMOS: 友達ゲート: out__alice__bob と in__alice__bob を partition=alice で 2 ポイントリード
  alt 片方でも欠ける（友達でない）
    FUNC-->>A: 403（友達でないので送れない）
  else 両方あり（相互マッチ＝友達）
    FUNC->>COSMOS: messages へ append
    FUNC->>REDIS: conv:alice:{pair} を無効化
    FUNC->>REDIS: conv:bob:{pair} を無効化
    Note over FUNC,REDIS: V2 は受信者(bob)を放置＝陳腐化。V3 は双方を無効化。
    FUNC-->>A: 201
  end
```

## 受信者側の読み取り（陳腐化が解消されている）

```mermaid
sequenceDiagram
  participant B as bob
  participant BFF
  participant API as FastAPI
  participant REDIS as Redis
  participant COSMOS as Cosmos

  Note over B: alice が直前に送信（conv:bob:{pair} は無効化済み）
  B->>BFF: GET /api/conversation?with=alice（Bearer）
  BFF->>API: 転送（X-User: bob）
  API->>REDIS: conv:bob:{pair} を見る → miss（無効化済み）
  API->>COSMOS: 会話を取り直して再構築
  API-->>B: 最新（alice の新着を含む）。TTL を待たない＝陳腐化なし
```

## 友達一覧の導出（積集合）

```mermaid
flowchart LR
  ME["me"]
  ACQ["自分の知り合い<br/>WHERE owner=me AND direction='out'<br/>（単一パーティション）"]
  INB["自分を知り合い登録している人(inbound)<br/>WHERE owner=me AND direction='in'<br/>（単一パーティション・dual-write のミラー）"]
  FRIENDS["友達 = out と in の積集合<br/>friends:me にキャッシュ"]
  ME --> ACQ
  ME --> INB
  ACQ --> FRIENDS
  INB --> FRIENDS
```
