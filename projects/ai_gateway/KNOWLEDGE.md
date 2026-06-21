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

## Responses API（Chat Completions ではなく）

推論呼び出しは `openai.responses.create` を使う（このリポジトリの方針。Chat Completions は非推奨）。

- `input` に文字列をそのまま渡せる（最小呼び出し）。複数ターンは配列で積む。
- `response.output_text` … 最終的なテキスト出力を結合してくれる便利プロパティ。
- GPT-4.1（非推論）/ GPT-5（推論）どちらも同じ Responses API で呼べる。
