# MERMAID — `registry` の構成と実験

## 構成図（リソースの関係）

```mermaid
graph TD
    subgraph RG["リソースグループ rg-container-registry"]
        ACR["ACR acrreg...<br/>(Basic / adminUserEnabled=false)<br/>repository: web : tag v1 → digest sha256:..."]
        UAMI["消費者 UAMI uami-reg-pull<br/>(後続サービスが pull に使う ID)"]
        ROLE["ロール割り当て AcrPull<br/>(scope = ACR)"]
    end

    Dev["手元の端末<br/>(az / Task / 任意で Docker)"]
    Next["後続ステップ Step2〜4<br/>aci / webapp / container-apps"]

    Dev -- "az acr build (クラウドビルド)" --> ACR
    Dev -- "az acr login (Entra トークン=キーレス) → push/pull" --> ACR
    ROLE -. "pull 許可を付与" .- UAMI
    UAMI -. "assign して keyless pull" .-> Next
    Next -- "pull web:v1" --> ACR
```

## 実験1: tag は動く参照 / digest は不変（`task digest-demo`）

```mermaid
sequenceDiagram
    participant D as 手元 (az acr build)
    participant A as ACR (repository: web)

    Note over A: 1) VERSION=v1 でビルド
    D->>A: az acr build --image web:v1
    A-->>D: tag v1 → digest A (sha256:aaa...)

    Note over A: 2) 同じタグ・中身だけ変更 (VERSION=v1-edited)
    D->>A: az acr build --image web:v1
    A-->>D: tag v1 → digest B (sha256:bbb...)

    Note over A: tag "v1" の指し先が A→B に移動<br/>digest A は dangling として残る
    D->>A: pull web@sha256:aaa... (digest 指定)
    A-->>D: 旧バージョン A を取得できる (不変)
```

## 実験2: admin user（共有パスワード）vs Entra トークン認証（`task admin-on` / `admin-off`）

```mermaid
graph LR
    Dev["手元の端末"]

    Dev -- "admin-on: adminUserEnabled=true" --> ON["az acr credential show<br/>= 共有 user/pass が見える<br/>(誰でも使える秘密=アンチパターン)"]
    Dev -- "admin-off: adminUserEnabled=false (既定)" --> OFF["credential show は失敗<br/>= 共有パスワード無し"]
    OFF --> Token["az acr login で<br/>Entra トークン認証=キーレス<br/>(共有秘密ゼロで push/pull)"]
```

## 実験3: 認証はそのまま・認可(AcrPull)で pull 可否が変わる（`task acrpull-setup`→`pull`→`revoke`→`pull`…）

UAMI（マネージド ID）は Azure リソースの中からしか使えない（IMDS 経由）ため、手元から成り代われない。
そこで **AcrPull だけ持つ SP を非特権 ID の代役**にして、ローカルから成功⇄403 を観測する。
ロールの出し入れ（`revoke`/`grant`）と pull（`acrpull-pull`）を分けてあり、**pull はロールを触らない**ので
反映待ちでも何度でも再実行して切り替わりを観察できる。

```mermaid
sequenceDiagram
    participant S as 手元 (SP の資格情報)
    participant A as ACR

    Note over S,A: SP 作成 + AcrPull 付与
    S->>A: docker login (認証)
    A-->>S: OK (ログインは通る)
    S->>A: docker pull web:v1 (認可=AcrPull あり)
    A-->>S: 成功

    Note over S,A: AcrPull を削除
    S->>A: docker login (認証)
    A-->>S: OK (認証はやはり通る)
    S->>A: docker pull web:v1 (認可=AcrPull なし)
    A--xS: 403 失敗
    Note over S,A: login(認証) は通るが pull(認可) は落ちる<br/>＝ 認証と認可は別物
```

> 注: ここで触るのは SP の代役実験。ACR に作った**消費者 UAMI 本人**を主語にした「AcrPull を外すと pull 失敗」は、
> UAMI を assign できる計算リソースが要るので **Step 2 (`aci`)** で行う（Step 1 は AcrPull を付けた土台まで）。
