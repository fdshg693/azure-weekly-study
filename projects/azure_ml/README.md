# azure_ml — Azure Machine Learning ハンズオン (Bicep + Python SDK v2 + Justfile)

記事 [`azure_ml.md`](azure_ml.md) を、実際に Azure で試せる最小構成に落としたプロジェクト。
記事が描く **「Workspace を中心に付随リソースがぶら下がり、その配下に Compute / Environment /
Data / Job / Model / Endpoint が並ぶ」** 地図を、次の 3 つで再現する。

- **Bicep** … Workspace と付随リソース (Storage / Key Vault / Application Insights) を宣言的に作る (記事 1〜2 章)
- **Python SDK v2 (`azure-ai-ml`)** … 学習ジョブ投入 → モデル登録 → エンドポイントデプロイ → 推論 の一連 (記事 3〜9 章)
- **Justfile** … 上記の手順をレシピ化

機械学習の中身はハンズオン体験重視の超最小構成: `y = 3x + 2` の合成トイデータ
(`data/toy-data.csv`) を Data asset として登録し、scikit-learn の線形回帰を 1 本学習するだけ。

基本の流れ (golden path) は `00`〜`05` の番号付きスクリプトで一本道。さらに 2 つの
**発展トラック**を用意していて、記事の概念を一歩踏み込んで体験できる:

- **Blue/Green デプロイ** (`flow/bluegreen.py`) … green を足してトラフィックを割合で寄せる無停止切替 (記事 9 章の応用)
- **MLflow ノーコードデプロイ** (`flow/mlflow_*.py`) … `score.py` を書かずに MLFLOW 形式モデルをデプロイする流儀 (記事 8〜9 章の対比)

## 構成

```
azure_ml/
├─ main.bicep                  # Workspace + 付随リソースを束ねる (記事 1〜2 章)
├─ main.bicepparam             # 既定パラメータ (すべて既定値で動く)
├─ modules/
│  ├─ storage.bicep           # 付随リソース: Storage (成果物・データ・既定 Datastore)
│  ├─ keyvault.bicep          # 付随リソース: Key Vault (シークレット保管庫)
│  ├─ monitoring.bicep        # 付随リソース: Log Analytics + Application Insights
│  └─ workspace.bicep         # Azure ML Workspace 本体 (SystemAssigned MI 付き)
├─ data/
│  └─ toy-data.csv             # 合成データ (x,y 列, y≈3x+2)。00 が Data asset に登録 (記事 6 章)
├─ src/                        # クラウドで動く学習コード (記事 5〜8 章)
│  ├─ train.py                # Data asset を読む → 線形回帰 → model.pkl (custom track)
│  ├─ train_mlflow.py         # Data asset を読む → 線形回帰 → MLFLOW 形式で登録 (mlflow track)
│  └─ conda.yml               # Environment 定義 (sklearn + 推論サーバ)
├─ onlinescoring/
│  └─ score.py                # scoring script init()/run() (記事 9 章。custom track 用)
├─ flow/                       # ローカルで動く SDK v2 オーケストレーション (記事 3 章)
│  ├─ _client.py              # MLClient ファクトリ (config.json から接続)
│  ├─ 00_register_data.py     # ★golden path: ローカル CSV を Data asset 登録 (記事 6 章)
│  ├─ 01_train_job.py         # Environment 作成 → Data asset 入力で command job
│  ├─ 02_register_model.py    # ジョブ出力を CUSTOM_MODEL 登録
│  ├─ 03_deploy_endpoint.py   # Managed Online Endpoint にデプロイ (blue 100%)
│  ├─ 04_invoke.py            # 推論リクエスト
│  ├─ 05_cleanup.py           # エンドポイント削除 (custom / mlflow 両方。課金停止)
│  ├─ bluegreen.py            # 発展A: green 追加 + トラフィック分割 (記事 9 章応用)
│  ├─ mlflow_train.py         # 発展B: MLflow 学習ジョブ (ジョブ内で Model 登録)
│  ├─ mlflow_deploy.py        # 発展B: MLFLOW モデルをノーコードデプロイ (score.py 不要)
│  ├─ mlflow_invoke.py        # 発展B: MLflow エンドポイントへ推論
│  └─ requirements.txt        # azure-ai-ml / azure-identity
├─ sample-request.json         # custom track の推論リクエスト ({"data": [[x], ...]})
├─ sample-request-mlflow.json  # mlflow track の推論リクエスト ({"input_data": {...}})
└─ justfile                    # 一連の手順をレシピ化
```

## 記事との対応

| 記事の章・概念 | このプロジェクトでの実現 |
|---|---|
| 1〜2 章 Workspace + 付随リソース | `main.bicep` + `modules/*.bicep` |
| 2 章 ACR は初回ビルド時に自動作成 | Bicep では作らない (Workspace に渡さない) |
| 3 章 `MLClient` / `DefaultAzureCredential` / `from_config` | `flow/_client.py` + `just write-config` |
| 4 章 Compute (まず Serverless) | `flow/01` で `compute` 未指定 = Serverless |
| 5 章 Environment | `src/conda.yml` + `flow/01` の `Environment` |
| 6 章 Datastore / Data asset / Input | `data/toy-data.csv` → `flow/00` で登録 → `flow/01` が `Input(URI_FILE, RO_MOUNT)` で読む |
| 7 章 command job | `flow/01` の `command(...)` |
| 8 章 Model 登録 (CUSTOM_MODEL) | `flow/02` (ジョブ出力を CUSTOM_MODEL 登録) |
| 8 章 Model 登録 (mlflow でそのまま) | `flow/mlflow_train.py` (ジョブ内で `log_model(registered_model_name=...)`) |
| 9 章 Online Endpoint + scoring script | `flow/03` + `onlinescoring/score.py` |
| 9 章 ノーコードデプロイ (MLFLOW 形式) | `flow/mlflow_deploy.py` (環境も `score.py` も書かない) |
| 9 章 blue/green デプロイ | `flow/bluegreen.py` (green 追加 → トラフィック分割) |
| 9 章 検証後に削除 | `flow/05` (`just cleanup`。両トラックのエンドポイントを削除) |

## 前提

- Azure CLI (`az login` 済み)。サブスクリプションの Contributor 以上を想定
- Python 3.10+ (ローカルで SDK を動かす)
- [`just`](https://github.com/casey/just) (任意。なくても下の各 `az` / `python` を直接叩けばよい)

## 手順 (just を使う場合)

```pwsh
# --- インフラ (記事 1〜2 章) ---
just group-create                 # 既定: rg-aml-demo / japaneast
just deploy                       # Workspace + Storage / Key Vault / App Insights
just write-config                 # Bicep 出力から SDK 用 config.json を生成

# --- ローカル SDK 環境 ---
just venv                         # .venv を作り azure-ai-ml / azure-identity を入れる

# --- ML フロー / golden path (記事 3〜9 章) ---
just register-data                # ⓪ ローカル CSV を Data asset 登録 (記事 6 章)
just train                        # ① Environment ビルド → Data asset 入力で学習ジョブ (初回は数分)
just register                     # ② ジョブ出力を CUSTOM_MODEL 登録
just deploy-endpoint              # ③ Online Endpoint にデプロイ (★ここから常時課金)
just invoke                       # ④ 推論。x=[0,1,2,10] → 約 [2,5,8,32] が返れば成功
just cleanup                      # ⑤ エンドポイント削除 (常時課金を止める)
```

`just all` で ⓪〜④ をまとめて実行できる (③ で課金が始まる点に注意)。

## 発展トラック

golden path を一周したら、記事の概念を一歩踏み込んで体験できる 2 つのトラックがある。
どちらも `00 register-data` 済みを前提とし、終わったら `just cleanup` で課金を止める。

### A. Blue/Green デプロイ (記事 9 章の応用)

`03` で作った Endpoint (窓口) はそのままに、裏の Deployment (VM 群) を無停止で差し替える。

```pwsh
# 03/04 のあと、cleanup の前に
just canary                       # green を追加し blue:90 / green:10 のカナリア
just invoke                       # 10% は green に流れる。問題なければ寄せる
just promote                      # green:100 へ (blue は待機)
just rollback-blue                # 問題が出たら blue:100 へ戻し green を削除
```

「Endpoint と Deployment を分ける」設計が、無停止のバージョン切替として効いてくる。

### B. MLflow ノーコードデプロイ (記事 8〜9 章の対比)

`train.py` + `score.py` (CUSTOM_MODEL を自作 scoring で出す流儀) に対し、MLFLOW 形式で
登録するともう一方の流儀になる: 学習ジョブの中で Model 登録まで済み、デプロイ時に
Environment も `score.py` も書かなくてよい。

```pwsh
just train-mlflow                 # 学習 + ジョブ内で MLFLOW モデル登録 (①+② を 1 本で)
just deploy-mlflow                # environment / score.py 無しでデプロイ (★常時課金)
just invoke-mlflow                # {"input_data": {...}} 形式で推論
just cleanup                      # 削除 (custom track の分も同時に消える)
```

`just all-mlflow` で ⓪ → 学習+登録 → デプロイ → 推論 をまとめて実行できる。
2 つの流儀を並べると、「scoring script を書く/書かない」の差がそのまま見える。

## 動作確認

- `just train` のログに `推定: y = 3.0xx x + 2.0xx (真値 3x + 2)` と `R2 ≈ 1.0` が出れば学習成功。
  Studio のジョブ画面 (ログ末尾に URL) で MSE / R2 のメトリクスも確認できる。
- `just invoke` のレスポンスが `[2.0..., 5.0..., 8.0..., 32.0...]` 付近なら、
  学習 → 登録 → デプロイ → 推論 がクラウド上で一周している。

## コストで事故らないために (記事 4・9 章)

- **学習は Serverless** (`flow/01` は `compute` 未指定)。Compute Cluster / Instance を作らないので
  アイドル課金が出ない。
- **Online Endpoint の裏 VM は常時起動 = 常時課金**。検証が終わったら必ず `just cleanup`。
- 全部まとめて消すなら `just destroy` (リソースグループごと削除。エンドポイント VM も消える)。

```pwsh
just destroy                      # az group delete --yes --no-wait
```

## 設計上の割り切り (記事と同じく POC 前提)

- **データは合成だが Data asset として扱う**。`data/toy-data.csv` (y≈3x+2 の合成データ) を
  `flow/00` で URI_FILE の Data asset に登録し、`flow/01` が `Input` + `azureml:toy-data@latest` で
  読み取り専用マウントする。これで「データ → ジョブ → モデル」の lineage が一本に繋がる (記事 6 章)。
- **既定 Datastore は資格情報 (キー) ベース**。Storage の共有キーアクセスを無効化していないので、
  ローカルからの code/data アップロードが追加の RBAC なしで通る。本番でアイデンティティベースに
  するなら Workspace MI への `Storage Blob Data Contributor` 付与が必要 (記事 2 章)。
- **ACR は Bicep で作らない**。初回 `just train` の Environment ビルド時に Azure ML が自動作成する
  (記事 2 章の注記どおり)。
- **ネットワーク隔離・MLOps パイプラインは対象外** (記事と同じスコープ)。

## トラブルシュート

- `just deploy` が Key Vault 名の競合で失敗する場合: 同名の論理削除済み Vault が残っている可能性。
  `az keyvault purge --name <kv 名>` で完全削除してから再デプロイする (論理削除は既定 7 日保持)。
- `Standard_DS2_v2` のクォータ不足でデプロイが失敗する場合: `flow/03_deploy_endpoint.py` /
  `flow/mlflow_deploy.py` / `flow/bluegreen.py` の `instance_type` を、リージョンで空きのある SKU に
  変える (記事 4 章: クォータは学習・デプロイで共有)。
