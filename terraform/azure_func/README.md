# Azure Functions × Static Web Apps × HTMX × Logic Apps デモ

Azure Static Web Apps から配信した HTMX ページから Azure Functions を直接叩く同期版に加え、**Logic Apps（入口）→ Service Bus（キュー）→ Worker Function（ワーカー）→ Table Storage** の非同期パイプラインを Logic App の `Until` ループで同期 RPC ふうにラップした構成も含む。

## 構成

### 同期版（既存）

```
[ブラウザ] ──hx-get──> [Function App] /api/random  →  "<span>42</span>"
```

### 非同期版（案B: Logic Apps で同期ラップ + Function プロキシ）

```
[ブラウザ (HTMX)]
  │  GET /api/async-random?min=..&max=..
  ▼
[Function App: /api/async-random]   ← 薄いサーバ側プロキシ
  │  POST { min, max } を Logic App callback URL に投げる
  │  （SAS 署名付き URL をブラウザに漏らさないため + 既存の CORS をそのまま流用）
  ▼
[Logic App (Consumption)]   ← 入口
  │ 1) jobId = guid()
  │ 2) Compose で {jobId,min,max} を組み立て
  │ 3) Service Bus に送信（ApiConnection: servicebus）
  │ 4) Until ループで /api/status?jobId=... を 3 秒間隔ポーリング
  │ 5) status=done を見つけたら body をそのまま Response
  ▼
[Service Bus Queue "jobs"]
  ▼
[Worker Function (Service Bus トリガー)]   ← ワーカー
  ├─ WORKER_SLEEP_SECONDS スリープ（重い処理を模擬）
  ├─ random.randint(min, max)
  └─ Table Storage "results" に {PartitionKey=job, RowKey=jobId, status=done, value=N}
       ▲
       └── /api/status?jobId=...（Logic App から呼ばれる）が読み出して JSON 返却
```

ポイント:

- **Logic App が「入口」**：HTTP 受信 → キュー投入 → 結果待ち → 応答 までを 1 つのワークフローで完結。
- **Service Bus が「キュー」**：入口とワーカーを疎結合に。Logic App の Service Bus コネクタ（ApiConnection）経由で送信。
- **Worker Function が「ワーカー」**：`@app.service_bus_queue_trigger` で受信。`time.sleep` で遅延を模擬。
- **Table Storage が「結果バス」**：ワーカーの出力先と、Logic App ポーリング先（`/api/status`）の共有先。
- **`/api/status` は常に 200**：未完なら `{"status":"pending"}`、完了なら `{"status":"done","value":N}`。Logic App の Until は本文で条件判定するため 404 を使うより扱いやすい。

## ファイル

| ファイル | 役割 |
| --- | --- |
| [provider.tf](provider.tf) | `azurerm ~> 3.0` プロバイダー設定 |
| [variables.tf](variables.tf) | 入力変数（Service Bus / Logic App / ワーカースリープ含む） |
| [resource_group.tf](resource_group.tf) | リソースグループ |
| [storage_account.tf](storage_account.tf) | Function App ランタイム用 Storage（Table もここに同居） |
| [service_plan.tf](service_plan.tf) | App Service Plan（Linux / Y1） |
| [function_app.tf](function_app.tf) | Function App 定義。`ServiceBusConnection` と `WORKER_SLEEP_SECONDS` を環境変数で注入 |
| [service_bus.tf](service_bus.tf) | Service Bus Namespace（Basic）、Queue `jobs`、認可ルール |
| [logic_app.tf](logic_app.tf) | Logic App ワークフロー、ServiceBus API Connection、各アクション |
| [static_web_app.tf](static_web_app.tf) | Azure Static Web Apps（Free SKU） |
| [outputs.tf](outputs.tf) | 各種 URL、Logic App コールバック URL（機密） |
| [justfile](justfile) | デプロイ・動作確認の簡便コマンド |
| [python/function_app.py](python/function_app.py) | `/api/random`（同期）+ `/api/async-random`（プロキシ）+ `worker`（SB トリガー）+ `/api/status`（Until ポーリング先） |
| [web/index.html](web/index.html) | HTMX 配信用ページ |

## 主な変数（デフォルト値）

- `location` = `Japan East`
- `function_app_name` = `func-simple-dev-seiwan`
- `static_web_app_name` = `swa-htmx-dev-seiwan`
- `servicebus_namespace_name` = `sbns-funcjobs-dev-seiwan`
- `logic_app_name` = `logic-funcjobs-dev-seiwan`
- `worker_sleep_seconds` = `5`（0〜60）
- `python_version` = `3.11`
- `service_plan_sku` = `Y1`

## 前提ツール

- [Terraform](https://developer.hashicorp.com/terraform/install)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)（`az login` 済み）
- [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local)（`func`）
- [Static Web Apps CLI](https://azure.github.io/static-web-apps-cli/)（`swa`）
- [just](https://github.com/casey/just)

## 使い方

```powershell
just init           # terraform init
just apply          # インフラを作成（Service Bus / Logic App / Function App / SWA 一式）
just deploy         # Function App と Static Web Apps を両方デプロイ
just open           # ブラウザで HTMX ページを開く
```

ワンショット:

```powershell
just up             # apply → deploy までまとめて
```

## 動作確認

```powershell
# 同期版（即時応答）
just test-func

# 非同期版を Logic App callback URL に直接 POST（curl で確認）
just test-logic
just test-logic 1 10       # min, max を渡す

# 非同期版を Function プロキシ経由で叩く（HTMX が実際に呼ぶのと同じ経路）
just test-async-func
just test-async-func 1 10
```

ブラウザ UI からは `just open` で開いた HTMX ページに **「乱数を生成（Logic App 経由・待つ）」** ボタンが出ているので、それをクリックすればよい。プロキシが内部で Logic App callback URL を叩き、結果を `<span>N</span>` 形式で返す。

`just test-logic` は Logic App の HTTP トリガー（SAS 署名付き callback URL）に POST し、Worker のスリープ完了後に `{"status":"done","value":N,"jobId":"..."}` が返ってくる。

Logic App の実行履歴は Azure ポータルの Logic App リソース → 「実行履歴」で各アクションごとに確認できる（Until が何回回ったかも見える）。

## 仕組みの要点

### Logic App の Until ループ条件

```
@equals(body('Get_status')?['status'], 'done')
```

- limit: `count = 60`, `timeout = PT5M` — Worker のスリープが長すぎてもいつかは抜ける安全弁。
- `Delay PT3S` を挟むことで Function 課金（≒ ステータス確認の HTTP 呼び出し）を抑制。

### Service Bus 送信のメッセージ本文

`Compose_message` で `{jobId, min, max}` を JSON オブジェクトに組み立て、Send_message の `body.ContentData` で `base64(string(outputs('Compose_message')))` として送る。Worker 側は `msg.get_body().decode('utf-8')` でそのまま JSON パース可能。

### Function 側のバインディング

- Worker: `@app.service_bus_queue_trigger(connection="ServiceBusConnection")` + `@app.table_output(table_name="results", connection="AzureWebJobsStorage")`
- Status: `@app.route(...)` + `@app.table_input(partition_key="job", row_key="{Query.jobId}")`
  - `{Query.jobId}` は URL クエリ `?jobId=...` の値を行キーに自動バインドする宣言式。
  - 行が無ければ `row` が空文字で渡ってくるので、`pending` を返せばよい（404 にしない）。

### Table は自動作成

`results` テーブルは事前に Terraform で作っていない。Functions の Table output バインディングが書き込み時に自動作成する。

## トラブルシュート

- **Logic App が `Get_status` で 4xx を連発する** → Function 未デプロイ。`just deploy-func` で関数コードを発行。
- **Worker が起動しない（キューが詰まる）** → `ServiceBusConnection` が無効。`terraform apply` で再注入し Function App を再起動。
- **API Connection が "Unconnected"** → `azurerm_api_connection.servicebus` の `parameter_values.connectionString` を確認。ポータルの Logic App → 「API 接続」で再認証する手もある。

## 後片付け

```powershell
just destroy
```
