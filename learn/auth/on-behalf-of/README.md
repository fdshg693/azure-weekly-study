# on-behalf-of — トークンを引き継ぐ（多段 API にアイデンティティを伝播）

`auth` の 6 つ目のプロジェクト（[PLAN.md](../PLAN.md) の案5）。これまでは「クライアント → 1 つの API」の 1 段だった。本プロジェクトは初めて **多段**（SPA → 中間 API(A) → 下流 API(B)）になる。

中心にある問いは **「受け取ったトークンを、その先の API にどう引き継ぐか」**。A が受け取るのは <code>aud=api://A</code> のトークンで、B は <code>aud=api://B</code> しか受け入れない。**だから受け取ったトークンはそのまま転送できない。** これを解くのが **On-Behalf-Of(OBO) フロー＝トークン交換**で、A が「このユーザートークンを B 宛に替えて」と頼むと、**主体（ユーザー）を保ったまま** B 宛のトークンが返る。

- **`aud` 境界**：トークンには宛先（`aud`）があり、宛先違いの API には使えない。案1（api-protect）で「`aud` を検証する」ことがなぜ重要だったかが、ここで効いてくる。
- **トークン交換（OBO）**：`grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer` ＋ A の `client_secret` ＋ `requested_token_use=on_behalf_of`。
- **アイデンティティ伝播**：交換後トークンの `name`/`oid` は元のユーザーのまま。A を経由しても「**そのユーザーとして**」B を呼べる。

> 学ぶ概念の整理は [KNOWLEDGE.md](./KNOWLEDGE.md)、フロー図と対比は [MERMAID.md](./MERMAID.md) を参照。

## 目的

- **`aud` 境界**を、実演で確かめる：受け取ったユーザートークンを *そのまま* B に転送すると **401**（`/api/chain-naive`）。OBO 交換してから呼ぶと **200**（`/api/chain-obo`）。同じログイン・同じ A 宛トークンのまま、転送は失敗・交換は成功になる対比が学びの中心。
- **OBO のトークン交換**を SDK 無しで露わにする（`confidential-web` が code→token 交換を fetch 1 本で見せたのと同じ流儀）。
- **中間層の委任同意**が OBO の前提であることを、`consent`/`revoke-consent` で**出し入れ**して体感する（取り消すと交換が AADSTS65001 で失敗＝502）。

## 前提条件

- **Azure CLI**（`az login` 済み）と、アプリ登録・クライアントシークレット発行・**委任許可への管理者同意**ができる権限のある Entra テナント（同意は**管理者権限**が要る）
- **Task**（[taskfile.dev](https://taskfile.dev)）と **PowerShell 7+**（`scripts/*.ps1` の実行）
- **Node.js 18+**（2 つの API の実行。依存は `jose` のみで初回に自動インストール。グローバル `fetch` を使うため 18 以上）
- **Python 3**（SPA のローカル配信に `python -m http.server` を使う）

## 構成

```
on-behalf-of/
├─ README.md          このファイル（手順・学習の流れ）
├─ KNOWLEDGE.md       新出用語（OBO / aud 境界 / トークン交換 / jwt-bearer / アイデンティティ伝播 / 中間層の委任同意）
├─ MERMAID.md         多段フロー図・naive 転送↔OBO 交換の対比・トークンの aud/主体の変化
├─ Taskfile.yml       タスク定義（呼び出しだけ。実体は scripts/*.ps1 に切り出し）
├─ scripts/           Taskfile から呼ぶ PowerShell
│  ├─ _lib.ps1            共有ヘルパー（.env 読み込み）
│  ├─ register.ps1        3 アプリ（B / A＝コンフィデンシャル / SPA）の登録・配線・シークレット発行
│  ├─ consent.ps1         A→B の委任許可に管理者同意（OBO の前提）
│  ├─ revoke-consent.ps1  上の同意を取り消し（OBO が AADSTS65001 で失敗するようになる）
│  ├─ gen-config.ps1      .env から src/config.js を生成（SPA は A 宛スコープだけ知る）
│  └─ unregister.ps1      3 つのアプリ登録を削除
├─ .env.example       TENANT_ID / SPA・A・B の各 ID / A のシークレット の雛形
├─ .gitignore         .env（★シークレット含む）・config.js・node_modules を無視
├─ src/               SPA（中間 API(A) だけを呼ぶ。B は知らない）
│  ├─ index.html      ログイン＋3 ボタン（/api/me・chain-naive・chain-obo）
│  ├─ auth.js         MSAL でログイン → A 宛トークン取得 → A を叩く
│  ├─ authConfig.js   MSAL 設定（apiScope は api://A/access_as_user）
│  └─ config.js       ★ .env から task config で生成（gitignore 済み）
├─ api-middle/        中間 API(A)：リソースサーバー兼コンフィデンシャルクライアント（OBO の主役）
│  ├─ server.js       A 宛トークンを検証 → OBO 交換 → B を呼ぶ。naive 転送の失敗も実演
│  └─ package.json    依存は jose だけ
└─ api-downstream/    下流 API(B)：普通のリソースサーバー
   ├─ server.js       aud=api://B のトークンだけ受け入れ、伝播したユーザーの身元を返す
   └─ package.json    依存は jose だけ
```

## 実行手順

すべてこの `on-behalf-of` ディレクトリで実行する。

### 1. アプリ登録＋シークレット発行（ユーザーが一度だけ実行）

`task register` が、**下流 API(B)**（普通のリソースサーバー）、**中間 API(A)**（リソースサーバー兼コンフィデンシャルクライアント＋シークレット）、**SPA** の 3 つを作り、配線する。A には「B を委任で呼ぶ」`requiredResourceAccess(type=Scope)` が入る。

```bash
task register     # 出力された SPA_CLIENT_ID / API_A_CLIENT_ID / API_A_CLIENT_SECRET / API_B_CLIENT_ID を控える（シークレットは一度きり表示）
task tenant       # テナント ID を表示
```

> このリポジトリの方針どおり、Azure 上にオブジェクトを作る操作は**ユーザーが実行**する（AI は実行しない）。

### 2. 設定の記入

```pwsh
Copy-Item .env.example .env
# .env を編集：TENANT_ID / SPA_CLIENT_ID / API_A_CLIENT_ID / API_A_CLIENT_SECRET / API_B_CLIENT_ID
#   （REDIRECT_URI / API_A_BASE_URL / ポート類は既定で可）
```

**`.env` はシークレットを含むので絶対にコミットしない**（`.gitignore` 済み）。

### 3. 2 つの API と SPA を起動する（まず consent 前）

ターミナルを 3 つ使う。

```bash
task api-downstream   # 別ターミナル①：下流 API(B) を http://localhost:3001 で待ち受け（起動しっぱなし）
task api-middle       # 別ターミナル②：中間 API(A) を http://localhost:3000 で待ち受け（起動しっぱなし）
task serve            # 別ターミナル③：SPA を http://localhost:5173 で配信（config も生成）
```

ブラウザで http://localhost:5173 を開き、**ログイン**する。

- **「A が受け取ったトークンを見る」（/api/me）→ 200**。`aud` が <code>api://A</code>、`name` はあなた。このトークンは A 宛なので、このままでは B（aud=api://B）には使えない。
- **「生トークンを B に転送」（chain-naive）→ B が 401**。A が *交換せず* ユーザートークンをそのまま B に投げた結果。`aud` が B 宛でないため弾かれる ＝ **`aud` 境界**。
- **「OBO 交換して B を呼ぶ」（chain-obo）→ まだ 502**。OBO 交換に必要な A→B の委任同意がまだ無い（AADSTS65001）。

### 4. 委任同意を与えて chain-obo を 200 に変える（このプロジェクトの肝）

```bash
task consent      # A→B の委任許可 access_as_user に管理者同意（OBO の前提）
```

ブラウザに戻り **「OBO 交換して B を呼ぶ」（chain-obo）** を押す → **200**。B の応答に乗る `name`/`oid` は **SPA でログインした本人**。A を経由しても「そのユーザーとして」B に到達した＝**アイデンティティ伝播**。

### 5. 後片付け

```bash
task unregister   # 3 つのアプリ登録を削除（シークレット・SP・委任同意も一緒に消える）
```

## 学習の流れ（設定を「出し入れ」して因果を確かめる）

1. **`aud` 境界**（核心その 1）：chain-naive は常に B が **401**。chain-obo は consent 後に **200**。同じログイン・同じ A 宛トークンのまま、**転送はできず・交換ならできる**。「トークンには宛先がある」を体で覚える。
2. **中間層の委任同意の出し入れ**（核心その 2）：`task revoke-consent` → chain-obo が **502**（OBO 交換が AADSTS65001 で失敗）。`task consent` → **200** に戻る。OBO は「A がユーザーの代理で B を呼ぶ」ので、**A→B の委任同意**が前提だと分かる。
   - 対比：`client-credentials-daemon` の `grant`/`revoke` は「アプリ許可（roles）」の同意＝`appRoleAssignment` だった。こちらは「委任許可（scp）」の同意＝`oauth2PermissionGrant`。**委任とアプリ許可で同意の置き場所が違う**。
3. **トークンの中身を見る**：chain-obo 成功時、B の応答の `aud` は <code>api://B</code>、`name` は本人、`azp/appid` は **A**。「A が、ユーザーとして」呼んでいる構図がクレームに表れる。/api/me の `aud`（api://A）と並べて、**交換の前後で aud が A→B に変わり、主体は変わらない**ことを確かめる。
4. **シークレットを壊す**（任意）：`.env` の `API_A_CLIENT_SECRET` を 1 文字変えて chain-obo → OBO 交換が **invalid_client** で失敗（502）。OBO 交換は A がコンフィデンシャルクライアントとして秘密を提示する、を確認。元に戻す。

## 補足

- **SPA は A だけを知り、B を知らない**：`config.js` の `apiScope` は <code>api://A/access_as_user</code>。B を呼ぶのは A の責務（OBO）。**多段の各段は「次の段」だけ知る**、という構造をフロント設定にも反映している。
- **A は二役**：リソースサーバー（SPA からのトークンを検証）かつクライアント（B を OBO で呼ぶ）。だから A だけがクライアントシークレットを持つ。B は普通のリソースサーバーで秘密を持たない。
- **B は CORS を付けない**：B を呼ぶのはブラウザではなく A（サーバー）だから。A は SPA(:5173) に呼ばれるので CORS 有り。「誰がブラウザで、誰がサーバーか」が CORS の有無に出る。
- 次の一歩は [PLAN.md](../PLAN.md) の案7（managed-identity）でこの A のシークレットを**消す**、あるいは案10（security-hardening）でトークン寿命・条件付きアクセスの作り込みへ。
