# AI Gateway 設計メモ（PLAN）

> このドキュメントは [README.md](README.md) の「今後の予定」を実現するための**設計の概要・実装ステップ・注意点**をまとめたもの。
> 実装の細かいコードには踏み込まず、「何を・どの順で・どこに気をつけて作るか」に集中する。

## 1. 今回のスコープ

README の「今後の予定」のうち、以下の 2 点を対象とする。

1. **様々な AI モデルを管理画面から簡単にデプロイ**
2. **デプロイした AI モデルを API 経由で呼び出し可能**

簡単のため、対象プロバイダは **Azure OpenAI（Microsoft Foundry の Azure OpenAI モデル）のみ** とする。
README の「将来機能」（外部プロバイダ・APIキー管理・カスタムエンドポイント・ログ/コスト管理）は本フェーズでは扱わない。
ただし将来拡張しやすいよう、§6 の方針だけ意識して設計する。

## 2. 一番大事な前提：2 つの「面」を分けて考える

Azure OpenAI の操作は、性質の異なる 2 つの API 群（plane）に分かれる。本プロジェクトの 2 機能はちょうどこの 2 面に対応する。

| 面 | 役割 | 本プロジェクトでの用途 | 代表的な手段 |
|----|------|------------------------|--------------|
| **コントロールプレーン**（管理面 / ARM） | リソースやモデルデプロイの作成・一覧・削除 | ①「管理画面からデプロイ」 | Azure CLI (`az cognitiveservices account deployment ...`)、ARM REST、Bicep/Terraform |
| **データプレーン**（推論面） | デプロイ済みモデルへの推論呼び出し（chat completions 等） | ②「API 経由で呼び出し」 | OpenAI 互換 API、`openai` SDK（`AzureOpenAI` クライアント） |

- コントロールプレーンとデータプレーンは **API バージョンも認証に必要な権限も別物**。混同しないこと。
- コントロールプレーンのリソース管理は API バージョン `2023-05-01` 以降（最新 GA は `2025-06-01`）。
- データプレーンの推論は別系統のバージョン（例：GA `2024-10-21` / `v1`）。
- この分離を理解していれば、「管理 UI = コントロールプレーンの薄いラッパー」「呼び出し API = データプレーンのプロキシ」という構造が自然に見えてくる。

参考: [Azure OpenAI REST API リファレンス（control / data plane）](https://learn.microsoft.com/en-us/azure/foundry/openai/reference)

## 3. アーキテクチャ概要

既存プロジェクト（[chatbot](../chatbot/)）と技術スタックを揃える：**Node.js + Express + EJS（管理UI）/ `@azure/identity` / `openai` SDK / Terraform（IaC）/ justfile**。

```text
                 ┌──────────────────────────────────────┐
   ブラウザ ──▶ │  管理UI (EJS画面)                      │
                 │   ├─ デプロイ一覧 / 作成 / 削除 ───────┼─▶ コントロールプレーン
                 │   └─ チャット試し打ち ────────────────┼─▶ データプレーン
                 │                                        │   (推論プロキシ)
                 │  Express バックエンド                  │
                 └───────────────┬──────────────────────┘
                                 │ Managed Identity / DefaultAzureCredential
                                 ▼
                 ┌──────────────────────────────────────┐
                 │  Azure OpenAI (Foundry) リソース       │
                 │   └─ モデルデプロイ (gpt-4o, ...)      │
                 └──────────────────────────────────────┘
```

- **「ゲートウェイ」は今回は自前の薄い Express プロキシ** とする。Azure には APIM ベースの本格的な "AI Gateway" 機能（負荷分散・トークン制限・観測性など）があるが、学習用途では過剰なので**まずは自作**で 2 面の流れを体験する。APIM 版は将来比較対象として §6 に記録。
  - 参考: [AI gateway capabilities in Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/genai-gateway-capabilities)

## 4. 実装ステップ

段階的に難しくしていく方針（READMEの学習スタイル）に沿って、小さく動かしながら進める。

### ステップ 0：土台づくり（IaC）
- Terraform で **Azure OpenAI（Foundry）リソース本体**だけを作る（モデルデプロイは敢えてまだ作らない＝アプリから作る対象として残す）。
- アプリが使う **Managed Identity** と **RBAC ロール割り当て**を用意（§5 の権限表を参照）。
- `.env` / `.env.example` にエンドポイント・リソース情報を切り出し（既存ルール準拠）。

### ステップ 1：呼び出し（データプレーン）を先に通す
- 「管理 UI」より先に、**手動で 1 つだけデプロイしたモデル**に対して推論呼び出しを通す。
- `openai` SDK の `AzureOpenAI` クライアントで、**デプロイ名**を指定して chat completions を叩く最小エンドポイントを Express に実装。
- ここで「デプロイ名で呼ぶ」「認証は Managed Identity」という勘所を確実に押さえる。

### ステップ 2：デプロイの「一覧」（コントロールプレーン読み取り）
- 既存デプロイを一覧表示する読み取り API を実装（`az cognitiveservices account deployment list` 相当）。
- あわせて「デプロイ可能なベースモデル一覧」も取得し、UI の選択肢にできるようにする（Models List API）。
- 読み取り系なのでガードレール上も安全に試せる。

### ステップ 3：デプロイの「作成・削除」（コントロールプレーン書き込み）
- UI から **モデル名・バージョン・SKU・容量(TPM)** を指定してデプロイを作成する API を実装。
- 削除 API も実装し、作成→一覧反映→削除のライフサイクルを UI 上で体験。
- 作成直後は provisioning に時間がかかるため、UI 側で状態（succeeded 等）を見せる。

### ステップ 4：管理 UI（画面）の統合
- 「デプロイ一覧 / 新規デプロイ / 削除 / チャット試し打ち」を 1 画面にまとめる。
- 「作ったモデルをその場で呼び出して結果が返る」体験を完成させる。

### ステップ 5：操作して挙動が変わることを体験（学習の仕上げ）
- READMEの学習方針に従い、**叩いて変化を体験する**ところまでやる。例：
  - RBAC ロールを外す → 管理操作が 403 になる／推論だけ通る、を確認。
  - TPM 容量を小さくしてデプロイ → 連打して `429 Too Many Requests` を観測。
  - 存在しないデプロイ名で呼ぶ → エラーを観測。

## 5. 認証と権限（ハマりどころ筆頭）

- 認証は **Managed Identity / `DefaultAzureCredential`** を基本とする（既存プロジェクト踏襲、API キーは将来機能）。
- **管理操作と推論操作で必要な RBAC ロールが違う**点に注意：

| 操作 | 必要ロール（目安） |
|------|--------------------|
| モデルデプロイの作成・削除（コントロールプレーン書き込み） | Cognitive Services Contributor |
| デプロイ/モデル一覧の取得（コントロールプレーン読み取り） | Cognitive Services Contributor 相当 |
| 推論呼び出し（データプレーン） | Cognitive Services OpenAI User |

- ロールの割り当てが反映されるまで時間差があることがある。403 が出たら**権限伝播待ち**も疑う。

参考: [Create and deploy an Azure OpenAI resource](https://learn.microsoft.com/en-us/azure/foundry-classic/openai/how-to/create-resource) / [Working with models（Models List / Update & deploy via API）](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/working-with-models)

## 6. その他の注意点

- **デプロイ名 ≠ モデル名**：Azure OpenAI は推論時に必ず「デプロイ名」を指定する（OpenAI 本家はモデル名）。UI でも両者を明確に区別して表示する。
- **リージョンごとにモデル可用性が違う**：選んだリージョンに無いモデルはデプロイできない。UI の選択肢は実際の可用性に合わせる。
- **クォータ（TPM）と SKU**：デプロイには容量（TPM）指定が要る。サブスクリプションのクォータ上限を超えると作成が失敗する。SKU（Standard / GlobalStandard / Provisioned 等）で課金・挙動が変わる。
- **コスト感**：デプロイの存在自体は基本無課金で、**推論呼び出しで従量課金**（Provisioned/PTU は予約課金で別）。学習中の作りっぱなしに注意し、ステップ5で削除まで体験する。
- **ガードレール**：CLAUDE.md の方針どおり、**明示指示が無い限り実デプロイはしない**。本プロジェクトはコード作成＋ローカル動作確認（必要なら読み取り系コマンド）までに留める。実リソース作成はユーザー指示後に行う。
- **API バージョンの混同**：管理用と推論用でバージョン体系が別（§2）。SDK/CLI が要求するバージョンを取り違えないこと。

## 7. 将来拡張への布石（今回はやらないが意識すること）

- **外部プロバイダ対応**：呼び出し層を「プロバイダ抽象」にしておくと、後で OpenAI 互換スキーマの他プロバイダを足しやすい。
- **APIM ベースの本格 AI Gateway へ移行**：負荷分散・トークン制限・観測性・コスト管理が必要になったら、自作プロキシを APIM の AI gateway 機能に置き換える比較を行う（[reference architecture](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/azure-openai-gateway-guide)）。
- **APIキー管理 / ログ・コスト管理**：データプレーンの前段にプロキシを置く構成のままなら、ここに計測・キー管理を足していける。
