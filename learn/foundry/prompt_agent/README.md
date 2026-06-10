# prompt_agent — Foundry プロンプトエージェント (Python だけで一周)

Foundry Agent Service の **プロンプトエージェント**を、リソース作成から会話まで
**ほぼ Python だけ**で体験するハンズオン。元ネタは公式クイックスタート:
<https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/prompt-agent?tabs=python>

クイックスタートは「プロジェクトさえあれば、あとはコード通り」という構成。つまり中身は
2 層に分かれる。本プロジェクトは **両層とも Python** で通すのが狙い (azure_ml が
「Bicep で基盤 → Python でデータプレーン」だったのに対し、ここは基盤も Python にする)。

| 層 | やること | 使う SDK |
|---|---|---|
| **コントロールプレーン** | Foundry リソース / プロジェクト / モデルデプロイの**作成** | `azure-mgmt-cognitiveservices` (`00`, `99`) |
| **データプレーン** | エージェントの**作成・会話** (クイックスタート本体) | `azure-ai-projects` 2.x + `openai` (`01`, `02`) |

> **1 箇所だけ `az` に頼る**: 自分にデータプレーンのロール (Foundry User) を付ける処理。
> `azure-mgmt-cognitiveservices` はロール割当 API を持たないため (公式明記)。
> どうしても Python で通したいなら `azure-mgmt-authorization` の `RoleAssignmentsClient`
> で代替できる (末尾「全部 Python にしたい場合」参照)。

## 構成

```
prompt_agent/
├─ requirements.txt        # 管理 SDK + データプレーン SDK
├─ _config.py              # config.json の読み書き (azure_ml の _client.py 相当)
├─ 00_provision.py         # ★control: account(kind=AIServices)+project+deployment を作り config.json を書く
├─ 01_create_agent.py      # ★data:    PromptAgentDefinition でエージェント作成
├─ 02_chat.py              # ★data:    conversation を作り 2 ターン会話 (履歴維持を確認)
├─ 99_cleanup.py           # control: deployment→project→account を削除
└─ justfile                # 上記をレシピ化
```

`config.json` は `00` が生成する (subscription_id を含むので `.gitignore` 済み)。

## クイックスタートとの対応

| クイックスタートの手順 | このプロジェクトでの実現 |
|---|---|
| 前提: Foundry プロジェクト + モデルデプロイ | `00_provision.py` (Bicep/ポータルの代わりに Python 管理 SDK) |
| 環境変数 `PROJECT_ENDPOINT` / `AGENT_NAME` | `00` が `config.json` に書き、`01/02` が読む |
| `pip install azure-ai-projects>=2.0.0` + `az login` | `requirements.txt` + 前提の `az login` |
| Create a prompt agent | `01_create_agent.py` (`agents.create_version` + `PromptAgentDefinition`) |
| Chat with the agent | `02_chat.py` (`conversations.create` + `responses.create`) |
| Clean up resources | `99_cleanup.py` / `just destroy` |

## 前提

- Azure CLI で `az login` 済み。アカウント作成には **Owner 相当** (Foundry Account Owner 等) が要る
- Python 3.10+
- [`just`](https://github.com/casey/just) (任意。なければ下の `python` を直接叩く)
- モデル (既定 `gpt-4.1-mini`) が使えるリージョン。既定は `eastus2`

## 手順 (just を使う場合)

```pwsh
just venv             # .venv を作り SDK を入れる
just group-create     # 任意: rg-foundry-agent / eastus2 を作る
just provision        # ⓪ account+project+deployment を作成 → config.json 生成
just grant-role       # 自分に project スコープの Foundry User ロールを付与 (反映に1〜2分)
just create-agent     # ① プロンプトエージェント作成
just chat             # ② 2 ターン会話。France の広さ → 首都 Paris が返れば成功
```

`just all` で ⓪ → ロール付与 → ① → ② をまとめて実行できる。

## 設定の上書き (.env / 環境変数)

`00_provision.py` の設定は **`.env` (このフォルダ直下) か環境変数**で変えられる。
`_config.py` が import 時に `.env` を読み込むので、`.env` に書けば各スクリプトに効く。
テンプレートは [.env.example](.env.example)。優先順位は **シェルの環境変数 > `.env` > 既定値**。

`.env` で指定する例 (コメントを外した行だけが効く):

```dotenv
ACCOUNT=foundry-agent-yourname   # ★グローバル一意にする
LOCATION=swedencentral           # モデルが無いリージョンなら変える
MODEL=gpt-4.1-mini
```

一回だけ変えたいときは環境変数でもよい:

```pwsh
$env:ACCOUNT = "foundry-agent-<your-initials>"; just provision
```

とくに **`ACCOUNT` (= カスタムサブドメイン名) はグローバルに一意**なので、既定が取られていたら変える。
サブスクリプションは `AZURE_SUBSCRIPTION_ID` (env/`.env`) を優先し、未設定なら `az` の既定サブスクリプションを使う。

## コストで事故らないために

- モデルデプロイは **GlobalStandard / capacity=1** = 従量課金 (使った分だけ)。常時起動 VM のような
  アイドル課金は無いが、放置せず終わったら消す。
- 検証が終わったら **`just cleanup`** (個別削除) か **`just destroy`** (RG ごと削除)。

## トラブルシュート

- **`01` が 401/403**: ロール反映待ち。`just grant-role` 後 1〜2 分おいて再実行。スコープが
  project になっているかも確認。
- **エンドポイントが繋がらない**: `00` が組み立てた `project_endpoint` が実際とズレている可能性。
  Foundry ポータルの welcome 画面 (またはプロジェクトの概要) のエンドポイントを `config.json` に貼り直す。
  `00` の実行ログにも `account.properties.endpoints` を出しているので照合する。
- **モデル/バージョンが無いと言われる**: リージョン依存。使える組み合わせを調べる:
  ```pwsh
  az cognitiveservices account list-models --name <account> --resource-group <rg> -o table
  ```
  見つかった `name` / `version` を `$env:MODEL` / `$env:MODEL_VERSION` に設定して再 `provision`。
- **`ACCOUNT` 名が衝突 / サブドメイン重複**: `$env:ACCOUNT` を一意な名前に変える。

## 全部 Python にしたい場合 (ロール付与も)

`just grant-role` の `az` を Python に置き換えるには `azure-mgmt-authorization` を使う:

```python
from azure.mgmt.authorization import AuthorizationManagementClient
# scope    = project の resource id
# principal= 自分の objectId (az ad signed-in-user show --query id -o tsv)
# role     = 53ca6127-db72-4b80-b1b0-d745d6d5456d (Foundry User)
auth.role_assignments.create(scope, uuid4(), {
    "role_definition_id": f"{scope_subscription}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-...",
    "principal_id": principal_object_id,
    "principal_type": "User",
})
```

ただし自分の objectId 取得に結局 `az ad signed-in-user show` 等が要るため、学習の本筋
(エージェント) からは外れる。まずは `az` 版で通すのがおすすめ。
