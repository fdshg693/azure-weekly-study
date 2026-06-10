# ephemeral_agent — Foundry エフェメラルエージェント (ツールを与えてテスト)

Foundry Agent Service の **エフェメラルエージェント** パターンを学ぶハンズオン。
元ネタは公式クイックスタート (Responses API):
<https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/responses-api?pivots=python>

**エフェメラル = エージェント定義（instructions / tools / model）が Foundry 側のリソース
ではなく、アプリのコード内に存在する**パターン。`prompt_agent` のように
`agents.create_version` でエージェントを作ったり消したりせず、毎回コードからエージェントを
組み立てて Responses API を呼ぶ。ライフサイクル管理（作成・更新・削除）が不要なのが利点。

このプロジェクトでは、エフェメラルエージェントに **2 種類のツール** を与えて挙動を確認する:

| ツール | 実行場所 | 中身 |
|---|---|---|
| **Web 検索** (`get_web_search_tool()`) | **サーバーサイド** (Foundry が実行) | 組み込みのホスト型ツール。ローカル実装不要 |
| **カスタムツール** (`lookup_person`) | **ローカル** (自分のプロセスが実行) | 名前から架空の個人情報を返すダミー関数 (`@tool`) |

## prompt_agent との違い

| | `prompt_agent` (プロンプトエージェント) | `ephemeral_agent` (エフェメラル) |
|---|---|---|
| エージェント定義の置き場所 | Foundry 側のリソース | アプリのコード内 |
| 作成/削除 | `create_version` / 必要 | 不要（プロセス内に一時生成） |
| 呼び出し方 | `agent_reference` で参照 | コードでエージェントを組み立てて `run` |
| SDK | `azure-ai-projects` + `openai` | **Agent Framework** (`agent-framework-foundry`) |
| リソース構築 | `00_provision.py` で作る | **作らない**（変数を注入するだけ） |

## 構成

```
ephemeral_agent/
├─ requirements.txt        # Agent Framework (FoundryChatClient) + 依存
├─ _config.py              # .env / 環境変数から endpoint・model を読む
├─ tools.py                # ★カスタムツール: lookup_person (架空の個人情報) を @tool で定義
├─ 01_function_tool.py     # ① カスタムツールだけのエージェント
├─ 02_web_search.py        # ② Web 検索ツールだけのエージェント
├─ 03_combined.py          # ③ 両方を持つエージェント（本題）
└─ justfile                # 上記をレシピ化
```

リソースを作らないので `00_provision.py` / `99_cleanup.py` は無い。
代わりに接続情報を `.env`（テンプレート [.env.example](.env.example)）で注入する。

## クイックスタートとの対応

| クイックスタートの手順 | このプロジェクトでの実現 |
|---|---|
| 環境変数 `FOUNDRY_PROJECT_ENDPOINT` / `FOUNDRY_MODEL` | `.env` に書き、`_config.py` が読む |
| `pip install agent-framework-foundry aiohttp` | `requirements.txt` |
| Create an agent / Add function tools | `01_function_tool.py` + `tools.py`（`@tool`） |
| Use the web search tool | `02_web_search.py`（`get_web_search_tool()`） |
| ローカルツール + Web 検索の併用 | `03_combined.py` |

## 前提

- Azure CLI で `az login` 済み（`AzureCliCredential` がそのトークンを使う）
- Python 3.10+
- [`just`](https://github.com/casey/just)（任意。なければ下の `python` を直接叩く）
- **すでにある Foundry プロジェクト + モデルデプロイ**
  （無ければ先に `prompt_agent` の `just provision` で作る。リソースは共有できる）

## 設定（.env）

[.env.example](.env.example) を `.env` にコピーして 2 つの値を入れる:

```dotenv
FOUNDRY_PROJECT_ENDPOINT=https://<account>.services.ai.azure.com/api/projects/<project>
FOUNDRY_MODEL=gpt-4.1-mini
```

`prompt_agent` を先に動かしているなら、生成された `prompt_agent/config.json` の
`project_endpoint` と `model_name` をそのまま流用できる。
`.env` は `.gitignore` 済み。優先順位は **シェルの環境変数 > `.env` > 既定値**。

## 手順（just を使う場合）

```pwsh
just venv          # .venv を作り Agent Framework を入れる
just function-tool # ① カスタムツール（ローカル実行）。佐藤 花子さんの架空情報が返れば成功
just web-search    # ② Web 検索（サーバーサイド実行）。最新情報が返れば成功
just combined      # ③ 両方。所属の調査(ローカル) + 関連ニュース検索(サーバー)を 1 回で
```

`just all` で ① → ② → ③ をまとめて実行できる。

直接叩く場合:

```pwsh
.venv/Scripts/python.exe 03_combined.py
```

## ツールの中身（学習ポイント）

- **カスタムツール** [tools.py](tools.py): `@tool(approval_mode="never_require")` を付けた
  普通の Python 関数。引数の `Annotated[str, Field(description=...)]` が LLM 向けの
  引数説明になる。モデルが必要と判断するとこの関数が **ローカルで** 呼ばれ、戻り値（架空の
  個人情報 JSON）を使って自然文で答える。実運用では DB / 社内 API に差し替える想定。
- **Web 検索ツール**: `FoundryChatClient.get_web_search_tool()` を `tools` に入れるだけ。
  検索の実行は **Foundry 側（サーバーサイド）** で行われ、ローカル実装は不要。

## トラブルシュート

- **401 / 403**: `az login` 済みか、そのアカウントがプロジェクトにアクセスできるロール
  （Foundry User 等）を持つか確認。`prompt_agent` の `just grant-role` 参照。
- **`FOUNDRY_PROJECT_ENDPOINT が未設定`**: `.env` を作ったか、値が正しいか確認。
- **モデルが見つからない**: `FOUNDRY_MODEL` がプロジェクトの **デプロイ名** と一致するか確認。
- **Web 検索が使えない**: プロジェクト側で Web 検索ツールが有効になっているか確認
  （リージョン / テナント設定に依存することがある）。`02` が失敗しても `01` は動く。
