# client-credentials-daemon — ユーザーのいない認証（アプリ自身として動く）

`auth` の 5 つ目のプロジェクト（[PLAN.md](../PLAN.md) の案4）。これまでの 4 プロジェクトはすべて **「ユーザーがログインする」** 前提だった（SPA でサインイン、あるいはサーバーがユーザーをログインさせる）。

本プロジェクトはその前提を外す。**バッチ・常駐デーモン・CI には人間がいない。** そこでアプリ自身の資格情報（クライアントシークレット）だけでトークンを取り、保護 API を呼ぶ —— **Client Credentials Flow** を学ぶ。

- **委任許可 vs アプリケーション許可**：これまでは「ユーザーの代理（委任 / `scp`）」だった。デーモンは「アプリそのもの（アプリケーション許可 / `roles`）」として動く。
- **ユーザーコンテキストの有無**：トークンに `name` も `scp` も無く、`idtyp=app`。主体（`sub`/`oid`）はデーモンの SP。
- **管理者同意**：委任は「サインインしたユーザーがその場で同意」。アプリケーション許可は「**管理者が事前にアプリへ付与**」。本プロジェクトの `grant`/`revoke` がこれ。

> 学ぶ概念の整理は [KNOWLEDGE.md](./KNOWLEDGE.md)、フロー図と対比は [MERMAID.md](./MERMAID.md) を参照。

## 目的

- `entra-spa-login` の「**ユーザーが同意して委任**」と、本プロジェクトの「**ユーザー不在・アプリ自身**」を正面から対比する。
- **委任スコープ（`scp`）とアプリケーション許可（`roles`）の違い**を、実際に届くトークンの中身で見比べる（SPA のトークンには `name`/`scp`、デーモンのトークンには `roles` だけ）。
- **`.default` スコープ**が client credentials で必須な理由（個別スコープを動的要求できない＝事前に管理者が与えた許可で動く）を体感する。
- 許可を `grant`/`revoke` で**出し入れ**して、同じデーモン・同じシークレットのまま `/api/tasks` が **200 ↔ 403** に変わることを確かめる。

## 前提条件

- **Azure CLI**（`az login` 済み）と、アプリ登録・クライアントシークレット発行・**アプリケーション許可の付与（管理者同意）**ができる権限のある Entra テナント（後者は**管理者権限**が要る）
- **Task**（[taskfile.dev](https://taskfile.dev)）と **PowerShell 7+**（`scripts/*.ps1` の実行）
- **Node.js 18+**（API とデーモンの実行。依存は `jose` のみで初回に自動インストール。グローバル `fetch` を使うため 18 以上）

> ⚠ このプロジェクトは **SPA を配信しない**。クライアントはブラウザではなく「デーモン（サーバー上で走る Node スクリプト）」。`config.js` の生成も無い。

## 構成

```
client-credentials-daemon/
├─ README.md        このファイル（手順・学習の流れ）
├─ KNOWLEDGE.md     新出用語（client credentials / 委任 vs アプリケーション許可 / .default / 管理者同意 / idtyp）
├─ MERMAID.md       client credentials フロー図・委任↔アプリ許可の対比・トークンの中身の違い
├─ Taskfile.yml     タスク定義（呼び出しだけ。実体は scripts/*.ps1 に切り出し）
├─ scripts/         Taskfile から呼ぶ PowerShell
│  ├─ _lib.ps1          共有ヘルパー（.env 読み込み）
│  ├─ register.ps1      API（アプリ許可ロール）＋デーモン（コンフィデンシャル＋シークレット）の登録・配線
│  ├─ grant.ps1         デーモンの SP にロールを付与（=アプリケーション許可の管理者同意）
│  ├─ revoke.ps1        付与を取り消し
│  ├─ show-grants.ps1   現在の付与を一覧
│  └─ unregister.ps1    2 つのアプリ登録を削除
├─ .env.example     TENANT_ID / CLIENT_ID / CLIENT_SECRET / API_CLIENT_ID の雛形
├─ .gitignore       .env（★シークレット含む）・node_modules を無視
├─ api/             自前 API（リソースサーバー）
│  ├─ server.js     Bearer を受け、署名/aud と roles（アプリ許可）を検証。scp は見ない
│  └─ package.json  依存は jose だけ
└─ daemon/          デーモン（クライアント）
   ├─ daemon.js     client credentials でトークン取得 → 中身表示 → /api/whoami・/api/tasks を呼ぶ
   └─ package.json  依存は jose だけ
```

## 実行手順

すべてこの `client-credentials-daemon` ディレクトリで実行する。

### 1. アプリ登録＋シークレット発行（ユーザーが一度だけ実行）

`task register` が、**アプリケーション許可ロール `Tasks.Process.All`** を定義した自前 API と、**コンフィデンシャルなデーモン**（クライアントシークレット付き）を作り、デーモンの `requiredResourceAccess` を **`type=Role`（アプリケーション許可）** で配線する。

```bash
task register     # 出力された CLIENT_ID / CLIENT_SECRET / API_CLIENT_ID を控える（シークレットは一度きり表示）
task tenant       # テナント ID を表示
```

> このリポジトリの方針どおり、Azure 上にオブジェクトを作る操作は**ユーザーが実行**する（AI は実行しない）。

### 2. 設定の記入

```pwsh
Copy-Item .env.example .env
# .env を編集：TENANT_ID / CLIENT_ID / CLIENT_SECRET / API_CLIENT_ID（API_PORT / API_BASE は既定で可）
```

**`.env` はシークレットを含むので絶対にコミットしない**（`.gitignore` 済み）。

### 3. API を起動 → デーモンを走らせる（まず grant 前）

```bash
task api          # 別ターミナルで。http://localhost:3000 で待ち受け（起動しっぱなし）
task run          # デーモンを 1 回実行：トークン取得 → 中身表示 → /api/whoami → /api/tasks
```

このとき：

- **`/api/whoami` は 200**。出力を見ると `name` が「なし」、`scp` が「なし」、`idtyp=app`。**ユーザーがいない**ことが分かる。
- **`/api/tasks` は 403**。まだアプリケーション許可を付与していないので、トークンに `roles` が無い。

### 4. 許可を付与して 200 に変える（このプロジェクトの肝）

```bash
task grant        # デーモンの SP に Tasks.Process.All を付与（=アプリケーション許可の管理者同意）
task grants       # 付与状況を確認
task run          # 取り直すと roles に Tasks.Process.All が乗り、/api/tasks が 200 になる
```

`app-roles-rbac` では**ユーザーに**ロールを割り当てた。ここでは**アプリ（の SP）に**割り当てる。**割り当て先がユーザーかアプリか**が、委任とアプリケーション許可の決定的な違い。

### 5. 後片付け

```bash
task unregister   # 2 つのアプリ登録を削除（シークレット・SP・割り当ても一緒に消える）
```

## 学習の流れ（設定を「出し入れ」して因果を確かめる）

1. **正常系**：手順 3〜4 のとおり、grant 前は `/api/tasks` が 403、grant 後は 200。
2. **許可の出し入れ**（核心）：`task revoke` → `task run` で **403 に戻る**。`task grant` → `task run` で **200 に戻る**。同じデーモン・同じシークレットのまま、**アプリへの許可**だけで可否が変わる。
   - 対比：`app-roles-rbac` では同じ操作を「**ユーザーへの**ロール割り当て」で行った。主体がユーザーかアプリかが違うだけで、構造は同じ。
3. **トークンの中身を見る**（委任との対比）：`task run` の「取得したアクセストークンの中身」を読む。`scp` が無い・`name` が無い・`idtyp=app`・`roles` だけがある。`entra-spa-login`／`api-protect` のトークンには `name` と `scp` があった。**その差が委任↔アプリ許可の実物。**
4. **シークレットを壊す**：`.env` の `CLIENT_SECRET` を 1 文字変えて `task run` → トークン取得が **`invalid_client`** で失敗する。`confidential-web` と同じく、**シークレットこそがコンフィデンシャルの資格情報**。元に戻す。
5. **`.default` を確かめる**（任意）：`daemon/daemon.js` の `SCOPE` を `api://<API_CLIENT_ID>/access_as_user` のような個別スコープに変えると、client credentials では受け付けられない（`.default` 必須）。「ユーザーがその場で同意する委任」ではなく「事前に管理者が与えた許可で動く」フローだから、と理解する。
6. **`requiredResourceAccess` の `type`**（対比・任意）：`register.ps1` はデーモン側を `type=Role`（アプリケーション許可）で配線している。委任なら `type=Scope` だった（`app-roles-rbac` の SPA 側）。**同じ「API へのアクセス要求」でも Role か Scope かでフローの前提が変わる**ことを意識する。

## 補足

- **API 側は CORS を付けていない**：相手はブラウザではなくサーバー（デーモン）だから。これも「ユーザー（ブラウザ）不在」の表れ。
- **API は `scp` を見ない**：client credentials のトークンに `scp` は無いため。代わりに `roles`（アプリケーション許可）を検証する。委任とアプリ許可で**検証するクレームが変わる**。
- **`grant` には管理者権限が要る**：アプリケーション許可の付与は管理者同意に相当する。ユーザーが自分で同意できる委任スコープとはここも違う。
- **シークレットの重荷**：このシークレットは「管理・漏洩・ローテーション」の重荷でもある。これを **消す**のが次の案7（managed-identity）・案8（workload-identity-federation）。本プロジェクトの「シークレットで動くデーモン」を「シークレットを持たないデーモン」に置き換えていく。
- 次の一歩は [PLAN.md](../PLAN.md) の案7（managed-identity、Azure 内のシークレットレス）／案5（on-behalf-of、受け取ったユーザートークンで下流 API を呼ぶ多段伝播）。
