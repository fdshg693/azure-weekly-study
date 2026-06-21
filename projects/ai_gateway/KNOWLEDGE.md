# KNOWLEDGE — AI Gateway

このプロジェクトで新しく出てきた用語・概念をまとめる
（chatbot プロジェクトで既出の `azurerm_cognitive_account` / Managed ID / `Cognitive Services OpenAI User` などは省略）。

## コントロールプレーン / データプレーン（control plane / data plane）

Azure OpenAI への操作は性質の違う 2 つの API 群に分かれる。本プロジェクトはこの 2 面の体験が主目的。

- **コントロールプレーン（管理面 / ARM）**: リソースやモデルデプロイの**作成・一覧・削除**。
  Azure Resource Manager 経由で、Bicep / Terraform / `az` CLI / 管理用 REST から叩く。
  リソース管理用の API バージョン（`2023-05-01` 以降、最新 GA `2025-06-01`）を使う。
- **データプレーン（推論面）**: デプロイ済みモデルへの**推論呼び出し**（chat completions 等）。
  OpenAI 互換 API / `openai` SDK から、デプロイ名を指定して叩く。推論用の別バージョン体系。

→ **API バージョンも必要な RBAC ロールも別物**。混同しないこと。

## ロールの使い分け（管理 vs 推論）

| 操作 | 必要ロール |
|------|-----------|
| モデルデプロイの作成・削除（コントロールプレーン書き込み） | `Cognitive Services Contributor` |
| 推論呼び出し（データプレーン） | `Cognitive Services OpenAI User` |

chatbot では推論用の OpenAI User しか使わなかったが、本プロジェクトは「デプロイ操作」も行うため
Contributor も必要になる。

## `local_auth_enabled = false`（キーレス強制）

`azurerm_cognitive_account` の設定。`false` にすると API キー認証を無効化し、
Microsoft Entra ID トークン（az login / Managed Identity）でのみアクセスできる。
本プロジェクトは「キー管理は将来機能・MI を基本」という方針なので既定を `false` にしている。
※ Entra トークン認証には `custom_subdomain_name` の設定が前提（chatbot でも設定済み）。

## デプロイ操作系の az CLI

- `az cognitiveservices account deployment list/create/delete` … コントロールプレーンのデプロイ操作。
- `az cognitiveservices account list-models` … そのアカウント（=リージョン）で**デプロイ可能なベースモデル**の一覧。
  リージョンごとにモデル可用性が違うため、UI の選択肢を作る材料になる。

## デプロイ名で呼ぶ（データプレーン推論の勘所）

OpenAI 本家は推論時に**モデル名**（`gpt-4.1` 等）を指定するが、Azure OpenAI は必ず**デプロイ名**を指定する。
デプロイ名はモデルをデプロイするときに自分で付ける任意の名前で、モデル名と一致させても別名にしてもよい。

- `openai` SDK の `AzureOpenAI` クライアントは `deployment` をコンストラクタで固定して作る。
  そのためデプロイ名ごとに 1 クライアント生成してキャッシュする（[app/openai-client.js](app/openai-client.js)）。
- `responses.create({ model: <デプロイ名> })` の `model` にもデプロイ名を渡す。
- 推論用の `apiVersion`（例 `2025-04-01-preview`）はコントロールプレーンのバージョン体系とは別物（§コントロールプレーン参照）。

## キーレス推論（`DefaultAzureCredential` + Bearer トークンプロバイダ）

`local_auth_enabled=false` でキーを無効化しているため、推論も Entra ID トークンで認証する。

- `DefaultAzureCredential` … ローカルでは `az login` の資格情報、Azure 上ではマネージド ID を自動で使う。
- `getBearerTokenProvider(credential, "https://cognitiveservices.azure.com/.default")` で
  トークンを自動取得・更新するプロバイダを作り、`AzureOpenAI({ azureADTokenProvider })` に渡す。
- chatbot プロジェクトと同じ方式（推論の認証は両プロジェクトで共通）。

## ARM REST でコントロールプレーンを読む（ステップ2）

デプロイ/モデルの一覧取得は ARM（Azure Resource Manager）REST を直接叩いて実装した（[app/arm-client.js](app/arm-client.js)）。
SDK（`@azure/arm-cognitiveservices`）も使えるが、**データプレーンとの違いをコード上で明示的に見せる**ため生 REST を選択。

データプレーン推論（[app/openai-client.js](app/openai-client.js)）との「3つの違い」:

| 観点 | データプレーン（推論） | コントロールプレーン（ARM 読み取り） |
|------|------------------------|--------------------------------------|
| 認証スコープ | `https://cognitiveservices.azure.com/.default` | `https://management.azure.com/.default` |
| API バージョン | 推論用（例 `2025-04-01-preview`） | ARM 用（GA `2025-06-01`） |
| 必要ロール | Cognitive Services OpenAI User | Cognitive Services Contributor 相当 |
| 宛先 | アカウントの endpoint（`*.openai.azure.com`） | `management.azure.com` の ARM リソースパス |

- スコープだけ差し替えて `getBearerTokenProvider(credential, "https://management.azure.com/.default")` で ARM トークンを取得。
- 認証情報（`DefaultAzureCredential`）自体は推論と共通。**同じ az login でもトークンの「宛先（スコープ）」が違う**のが要点。
- Node 20+ の global `fetch` で ARM REST を直接 GET（追加の HTTP ライブラリ不要）。

### ARM のリソースパスと使った 2 つの読み取り API

ベースは `https://management.azure.com` + アカウントのフルリソース ID（`AZURE_OPENAI_ACCOUNT_ID`、terraform output `openai_account_id` と同値）。
1 つの env から subscription / resourceGroup / account 名を正規表現で取り出している。

- `GET .../accounts/{account}/deployments?api-version=2025-06-01`
  … 作成済みデプロイ一覧（`az ... deployment list` 相当）。`name`=デプロイ名、`properties.model.name`=モデル名、`properties.provisioningState`=状態、`sku.{name,capacity}`。
- `GET .../accounts/{account}/models?api-version=2025-06-01`
  … そのアカウント（=リージョン）でデプロイ可能なベースモデル一覧（`az ... list-models` 相当）。`value[].{name,version,format,skus,maxCapacity}`。

> 「コントロールプレーン読み取り = ARM の薄いプロキシ」という PLAN §3 の構造がそのままコードに現れる。

## ARM REST でデプロイを作成/削除する（ステップ3）

読み取り（ステップ2）と同じパス体系のまま、HTTP メソッドを変えるだけで書き込みになる。
`armRequest(method, path, body)` に一般化し、GET/PUT/DELETE を 1 経路で扱う（[app/arm-client.js](app/arm-client.js)）。

- **作成/更新**: `PUT .../accounts/{account}/deployments/{name}?api-version=2025-06-01`
  - リクエストボディ: `{ "sku": { "name": <SKU>, "capacity": <TPM> }, "properties": { "model": { "format": "OpenAI", "name": <モデル名>, "version": <バージョン> } } }`
  - **PUT は冪等**: 同じデプロイ名なら新規作成、既存なら設定更新になる（`az ... deployment create` と同じ感覚）。
- **削除**: `DELETE .../accounts/{account}/deployments/{name}?api-version=2025-06-01`

### LRO（Long-Running Operation = 長時間処理）

デプロイの作成/削除は**即座には完了しない**。ARM はまず受理し（`provisioningState` が `Accepted`/`Creating`）、
バックグラウンドでプロビジョニングを進める。

- そのため作成 API は**完了を待たずに**初期状態を返し、UI 側は `GET /deployments` で
  `state` が `Succeeded` になるまで**ポーリング**して進捗を見せる（PLAN §4 ステップ3 の「状態を見せる」）。
- 削除も同様に LRO（202 Accepted で受理）。本文が空のことがあるため、`armRequest` は空応答を `null` として扱う。

### 容量(TPM) / SKU / クォータ

- `capacity` はデプロイの**スループット上限（TPM: Tokens Per Minute 単位）**。サブスクリプションの
  クォータ上限を超えて指定すると作成が **4xx で失敗**する（ステップ5 で体験する観測点）。
- `sku`（`Standard` / `GlobalStandard` / `Provisioned` 等）で課金・配置・挙動が変わる。
  可用な SKU は `GET /models` の各モデルの `skus` で分かる（ステップ2 で取得済み）。

## Responses API（Chat Completions ではなく）

推論呼び出しは `openai.responses.create` を使う（このリポジトリの方針。Chat Completions は非推奨）。

- `input` に文字列をそのまま渡せる（最小呼び出し）。複数ターンは配列で積む。
- `response.output_text` … 最終的なテキスト出力を結合してくれる便利プロパティ。
- GPT-4.1（非推論）/ GPT-5（推論）どちらも同じ Responses API で呼べる。
