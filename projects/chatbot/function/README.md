# 共有メモ Function（Azure Functions / Table Storage）

全ユーザー共有のメモを CRUD する Azure Function。チャットアプリ（`../app`）から、
**人の手動 UI（`/memos`）でも、AI のツール呼び出し（`list_memos` ほか）でも**操作できる。

## このプロジェクトの学習ポイント（OBO との対比）

既存の `get_user_profile` ツールは **OBO（サインイン本人の委任権限）** で Graph を叩いていた。
こちらのメモ機能は対になる **「アプリ自身（マネージド ID）の権限で、保護された下流 API を呼ぶ」**
＝アプリ間（daemon）認証を学ぶ。

| | get_user_profile（既存） | メモ Function（本プロジェクト） |
| --- | --- | --- |
| データ | サインイン本人のもの | 全ユーザー共有 |
| 認証 | OBO（委任） | Managed Identity（アプリ間 / app role） |
| トークン aud | Microsoft Graph | `api://<func-app-id>`（この Function） |
| 認可の単位 | ユーザーの同意（scope） | アプリに割り当てた app role `Memo.ReadWrite` |

## 構成

```
[Web App] --MIトークン(api://<func>/.default, role=Memo.ReadWrite)--> [Function App]
                                                                        │ EasyAuth(Entra) で検証
                                                                        │ + コードで roles を確認
                                                                        │ Function MI (Storage Table Data Contributor)
                                                                        ▼
                                                                [Storage Account / Table "memos"]
```

- Function 自身も **キーレス**: `MEMO_STORAGE_ACCOUNT_URL` + `DefaultAzureCredential` で Table を読み書き
  （`Storage Table Data Contributor` ロール）。アプリ本体が OpenAI / Key Vault を MI で叩くのと同じ思想。

## ファイル

| ファイル | 役割 |
| --- | --- |
| [src/functions/memos.js](src/functions/memos.js) | HTTP ルート（`/api/memos`・`/api/memos/{id}`）。`x-ms-client-principal` の `roles` を検証 |
| [src/memoStore.js](src/memoStore.js) | Table Storage への CRUD（MI / 接続文字列を環境変数で切替） |
| [host.json](host.json) | Functions ランタイム設定（拡張バンドル v4） |
| [local.settings.json.example](local.settings.json.example) | ローカル実行用の設定サンプル（コピーして使う） |

## API

| メソッド | パス | 内容 |
| --- | --- | --- |
| GET | `/api/memos` | 一覧（`{ memos: [...] }`） |
| GET | `/api/memos/{id}` | 1 件取得 |
| POST | `/api/memos` | 作成（body: `{ title, body? }`） |
| PATCH | `/api/memos/{id}` | 更新（部分更新） |
| DELETE | `/api/memos/{id}` | 削除 |

## ローカル実行（Azure 不要、Azurite + Core Tools）

```powershell
# 別ターミナルで Table エミュレータを起動
azurite

# このフォルダで
cp local.settings.json.example local.settings.json
npm install
func start            # http://localhost:7071/api/memos
```

アプリ側（`../app`）から繋ぐには `app/.env` に `MEMO_API_BASE_URL=http://localhost:7071` を設定する
（ローカルは EasyAuth が無いので `MEMO_API_SCOPE` は空のまま）。

> アプリ側で `MEMO_API_BASE_URL` を設定しなければ、Function を立てずにアプリ内のインメモリ Mock で
> AI ツールと手動 UI の配線だけ試せる（`../app/memos.js`）。

## Azure へのデプロイ

親フォルダの [../justfile](../justfile) を使う:

```powershell
just apply          # Storage / Function App / ロールを作成（memos.tf）
just func-deploy    # この関数コードを Function App へ publish
just memo-api-setup # Entra で保護し Web App MI に app role を割り当て
just apply          # memo.auto.tfvars 反映で EasyAuth 有効化
```

新出用語は [KNOWLEDGE.md](KNOWLEDGE.md) を参照。
