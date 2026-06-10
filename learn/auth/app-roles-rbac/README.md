# app-roles-rbac — 認証から認可へ（App ロールで「何をしてよいか」を変える）

`auth` の 3 つ目のプロジェクト（[PLAN.md](../PLAN.md) の案2）。`api-protect` で作った「保護された自前 API」を土台に、**認証（誰か）と認可（何をしてよいか）は別物**であることを体で確かめる。

`api-protect` までは「正しいトークンを持つ相手か」だけを見ていた。ここではその先、**同じログインユーザーでも、割り当てられた役割（App ロール）によって出来ることを変える**。鍵になるのは、1 つのアクセストークンに乗る 2 つのクレームの違い：

- **`scp`（スコープ）** … 「**アプリ（SPA）がユーザーの代理で要求した操作範囲**」。クライアントが要求し、同意で決まる。
- **`roles`（ロール）** … 「**主体（ユーザー）に割り当てられた役割**」。管理者がユーザー／グループに割り当てる。

> 学ぶ概念の整理は [KNOWLEDGE.md](./KNOWLEDGE.md)、フロー図は [MERMAID.md](./MERMAID.md) を参照。

## 目的

- 自前 API（リソースサーバー）に **App ロール**（`Tasks.Read` / `Tasks.Write`）を定義し、ユーザーに割り当てる。
- 発行されたアクセストークンの **`roles` クレーム**を見て、エンドポイントごとに**クレームベースで認可**を出し分ける。
- **`scp` と `roles` の違い**を、1 つのトークンの中で並べて確認する。
- ロールを**出し入れ**して、**同じユーザーの可否が変わる**（200 ↔ 403）ことを体感する。

## 前提条件

- **Azure CLI**（`az login` 済み）と、アプリ登録 **および App ロールの割り当て**ができる権限のある Entra テナント
  - ※ App ロールをユーザーに割り当てるには管理者権限（またはアプリ所有者＋十分な権限）が要ることがある。
- **Task**（[taskfile.dev](https://taskfile.dev) のコマンドランナー）と **PowerShell 7+**（`scripts/*.ps1` の実行）
- **Node.js 18+**（自前 API の実行。依存は `jose` のみで `task api` 初回に自動インストール）
- **Python 3.7+**（SPA のローカル配信に `python -m http.server` を使用）
- モダンブラウザ（`http://localhost` で開く）

## 構成

```
app-roles-rbac/
├─ README.md        このファイル（手順・学習の流れ）
├─ KNOWLEDGE.md     新出用語（認可 / RBAC / App ロール / scp と roles の違い / クレームベース認可 / ロール割り当て）
├─ MERMAID.md       認可フロー・scp と roles の出どころ・検証ロジックの図
├─ Taskfile.yml     タスク定義（呼び出しだけ。実体は scripts/*.ps1 に切り出し）
├─ scripts/         Taskfile から呼ぶ PowerShell（巨大ワンライナーを避けるため）
│  ├─ _lib.ps1          共有ヘルパー（.env 読み込み）
│  ├─ register.ps1      2 つのアプリ登録(az, App ロール込み)を作成・配線
│  ├─ assign-role.ps1   ユーザーに App ロールを割り当て
│  ├─ unassign-role.ps1 App ロールの割り当てを解除
│  ├─ list-roles.ps1    割り当て済みロールを一覧
│  ├─ gen-config.ps1    .env → src/config.js を生成
│  └─ unregister.ps1    アプリ登録を削除
├─ .env.example     TENANT_ID / SPA_CLIENT_ID / API_CLIENT_ID / REDIRECT_URI / API_BASE_URL の雛形
├─ .gitignore       .env・生成物 src/config.js・api/node_modules を無視
├─ api/             リソースサーバー側
│  ├─ server.js     入口検証(署名/aud/scp)＋ roles でエンドポイント別の認可
│  └─ package.json  依存は jose だけ
└─ src/             SPA（クライアント側）。api-protect をロール出し分け用に拡張
   ├─ index.html    ログイン / 権限を見る / 一覧(Read) / 追加(Write) / ログアウト
   ├─ authConfig.js MSAL 設定（apiRequest は forceRefresh でロール変更を毎回反映）
   ├─ auth.js       ログイン処理＋保護エンドポイント呼び出し
   └─ config.js     ← .env から `task config` で生成（gitignore 済み）
```

## 実行手順

すべてこの `app-roles-rbac` ディレクトリで実行する。

### 1. アプリ登録（ユーザーが一度だけ実行）

`api-protect` と同じく「自前 API」「SPA」の **2 つのアプリ登録**を作る。違いは、**自前 API 側に App ロール `Tasks.Read` / `Tasks.Write` を定義**する点。`task register` が委任スコープと App ロールの両方を込みで作成・配線する。

```bash
task register     # 出力された API_CLIENT_ID と SPA_CLIENT_ID を控える
task tenant       # テナント ID を表示
```

> このリポジトリの方針どおり、Azure 上にオブジェクトを作る／割り当てる操作は**ユーザーが実行**する（AI は実行しない）。

### 2. 設定の記入

`.env.example` をコピーして `.env` を作り、上で得た値を入れる。

```pwsh
Copy-Item .env.example .env
# .env を編集：TENANT_ID / SPA_CLIENT_ID / API_CLIENT_ID（REDIRECT_URI / API_BASE_URL は既定で可）
```

### 3. 自分にロールを割り当てる（ここが認可の肝）

まずは **Read だけ**割り当ててみる（Write はあえて割り当てない）。

```bash
task assign -- Tasks.Read     # 現在サインイン中のユーザーに Tasks.Read を割り当て
task roles                    # 割り当て済みロールを確認（Tasks.Read だけのはず）
```

### 4. 自前 API を起動（別ターミナル）

```bash
task api          # 初回は jose を npm install → http://localhost:3000 で待ち受け
```

### 5. SPA を配信してログイン → ロールで可否が変わるのを見る

別のターミナルで：

```bash
task serve        # = task config（src/config.js 生成）→ http://localhost:5173 を配信
```

ブラウザで <http://localhost:5173> を開き、

1. **「ログイン」** … サインイン（ID トークンのクレームが出る）
2. **「自分の権限を見る」** … `/api/me`。`scp`（access_as_user）と `roles`（Tasks.Read）が**別物として並ぶ**ことを確認
3. **「タスク一覧を見る（Tasks.Read 必要）」** … Read を持つので **200**。タスク一覧が返る
4. **「タスクを追加（Tasks.Write 必要）」** … Write が無いので **403 Forbidden**。「ログインはできている（認証 OK）が、その操作の権限が無い（認可 NG）」

### 6. ロールを出し入れして因果を確かめる

```bash
task assign -- Tasks.Write    # 追加権限を付与
# → SPA で「タスクを追加」を押し直すと 201（forceRefresh で新しい roles が反映される）

task unassign -- Tasks.Read   # 閲覧権限を剥奪
# → SPA で「タスク一覧を見る」を押し直すと 403 に変わる
```

### 7. 後片付け

```bash
task unregister   # .env の SPA_CLIENT_ID / API_CLIENT_ID のアプリ登録を削除（ロール割り当ても一緒に消える）
```

## 学習の流れ（設定を「出し入れ」して因果を確かめる）

「スイッチを出し入れして、何が効いているか切り分ける」を**認可（ロール）**で行う。

1. **scp と roles を見比べる**：「自分の権限を見る」で、同じトークンに `scp`（アプリの許可）と `roles`（ユーザーの役割）が**別々に**乗ることを確認する。
2. **ロールあり＝200 / なし＝403**：Read だけの状態で「一覧」は 200、「追加」は 403。**認証は通っているのに操作で弾かれる**＝認可の壁。
3. **ロールを足す**：`task assign -- Tasks.Write` → 「追加」が 201 に変わる。**同じユーザー・同じログインのまま可否が変わる**ことを体感する。
4. **ロールを剥がす**：`task unassign -- Tasks.Read` → 「一覧」が 403 に変わる。
5. **roles を空にする**：両方 unassign すると `roles` クレーム自体が消え、`/api/me` は 200 だが `Tasks.*` は全部 403。「**役割ゼロのユーザー**」を観察する。
6. **scp を壊すと?**（対比）：`api/server.js` の `REQUIRED_SCOPE` をでたらめにすると、ロールがあっても入口で 403。**scp（アプリの許可）と roles（ユーザーの役割）は別レイヤー**だと分かる。

## 補足

- **トークンの再取得が要る**：ロールの割り当て／解除は、**次に発行されるトークン**から反映される。本 SPA は `apiRequest.forceRefresh=true` でボタンを押すたびに取り直すので、`assign`/`unassign` 後はボタンを押し直すだけで反映される（実運用では毎回リフレッシュしない）。
- **3 ターミナル想定**：`task api`（API）と `task serve`（SPA）は別プロセス。ロールの出し入れ（`task assign -- ...` 等）はさらに別ターミナルで行うと観察しやすい。
- **`roles` の検証・解釈責務はリソースサーバー（`api/server.js`）にある**。クライアントは表示のためにデコードするだけで、認可判断はしない。
- **グループクレームとの関係**：本サンプルは App ロール（アプリが定義する役割）を使う。Entra ではグループメンバーシップを `groups` クレームで運ぶ手もあるが、グループ ID は環境依存で再利用しにくいため、アプリ内認可は App ロールが扱いやすい（[KNOWLEDGE.md](./KNOWLEDGE.md) 参照）。
- 次の一歩は [PLAN.md](../PLAN.md) の案3（confidential-web）や案4（client-credentials-daemon）。「**誰が・どこで認証するか**」のバリエーションへ広がる。案2 で見た「**アプリの許可 (scp) と主体の権限 (roles)**」の区別は、案4 の「**委任許可 vs アプリケーション許可**」の理解に直結する。
