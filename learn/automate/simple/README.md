# Container Apps Job で「起動して終了する仕事」を自動化するプロジェクト

`automate` トピックの最初のプロジェクト。**Azure Container Apps Jobs** を主役に、
**「常駐する App ではなく、起動 → 仕事 → 終了 が 1 回で完結する Job」** を cron で定期実行する、
最小構成の「自動化」を体験する。

func（コードで書くサーバーレス）や AKS（コンテナを常駐させる基盤）に対し、ここでの主役は
**「コンテナを 1 回だけ走らせて終わらせる」実行モデル**そのもの。

## 仕組み

```
            ┌──────────────────────────────────────────┐
            │  Container Apps Environment (cae-...)     │
 cron */5   │   ┌────────────────────────────────────┐ │
 ──────────▶│   │  Job (job-...-hello)               │ │   stdout
 (定期起動) │   │   triggerType = Schedule           │ │ ─────────▶ Log Analytics
            │   │   実行ごとに worker コンテナを起動  │ │            (law-...)
 az job     │   │   → worker.py → exit 0/1           │ │
 start ────▶│   └────────────────────────────────────┘ │
 (手動起動) └──────────────────────────────────────────┘
                         ▲ pull (MI + AcrPull)
                    ACR (acr...) ◀── az acr build ./app (hello-job:v1)
```

- cron（既定 `*/5 * * * *` = 5 分ごと, **UTC**）で Job が自動起動し、`worker.py` が
  1 行ログを出して数秒後に終了する。これが 1 回の **実行 (execution)**。
- `az containerapp job start`（`just start`）で**手動でも即時起動**できる。
- worker は終了コードで成否を表す。`FAIL_JOB=true` なら `exit 1` → 実行は **Failed** になり、
  `replicaRetryLimit` の回数だけリトライされる。

## App と Job の違い（このトピックの肝）

| | Container **App** | Container **Job** |
| --- | --- | --- |
| 実行モデル | 常駐（リクエストを待ち続ける） | 起動 → 処理 → **終了** |
| 主な用途 | API / Web / 常駐ワーカー | バッチ・定期処理・キュー消費 |
| 成否 | プロセスが生きているか | コンテナの**終了コード** |
| スケール | レプリカ数（同時処理量） | 実行（execution）と、その中のレプリカ |
| トリガー | HTTP / イベント | **Manual / Schedule / Event(KEDA)** |

このプロジェクトは **Schedule トリガー**を主役にし、手動起動も併用する。Event（キュー駆動）は
次プロジェクトの題材（→ [../CLAUDE.md](../CLAUDE.md)）。

## 作られるもの

- リソースグループ（`rg-automate-simple`）
- Log Analytics Workspace（`law-cajob`）… stdout の保存先
- Container Apps Environment（`cae-cajob`）… Job が動く実行環境
- Azure Container Registry（`acrcajob...` / Basic / admin user 無効）
- User-Assigned Managed Identity（`uami-cajob`）+ ACR への **AcrPull** ロール
- Container Apps Job（`job-cajob-hello` / Schedule トリガー）

## ファイル

| ファイル | 役割 |
| --- | --- |
| [main.bicep](main.bicep) | 全体のオーケストレーション（環境モジュール + Job モジュール） |
| [main.bicepparam](main.bicepparam) | 既定パラメータ（実験時は justfile が `--parameters` で上書き） |
| [modules/environment.bicep](modules/environment.bicep) | Log Analytics / Environment / ACR / MI + AcrPull |
| [modules/job.bicep](modules/job.bicep) | **Job 本体**（cron / リトライ / 並列度などの実験パラメータを集約） |
| [app/worker.py](app/worker.py) | 起動 → ログ → 数秒 → `exit 0/1` のワーカー（標準ライブラリのみ） |
| [app/Dockerfile](app/Dockerfile) | `CMD ["python","worker.py"]`（EXPOSE も常駐コマンドも無い） |
| [app/.env.example](app/.env.example) | ローカル実行用の env 雛形 |
| [justfile](justfile) | デプロイ・ビルド・手動起動・履歴確認・各種因果実験 |

## 使い方

### 前提
- `az login` 済み、Azure CLI に `containerapp` 拡張（初回は自動で導入を促される）。
- `just` がインストール済み。
- イメージは ACR Tasks（`az acr build`）でクラウド側ビルドするので、ローカル Docker は不要。

### 1. デプロイ & イメージビルド

```powershell
az login
just group-create        # リソースグループ作成
just up                  # = deploy (Bicep) → build (az acr build)
just outputs             # ACR 名 / Job 名 / Log Analytics ID を確認
```

> `deploy` の時点で Job は作られるが、`build` 前はイメージが無いので実行すると失敗する。
> `up` で続けてビルドすれば、次の cron 起動（または `just start`）から成功する。

### 2. 動かして観察する

```powershell
just start            # 手動で 1 回起動（cron を待たずに試せる）
just executions       # 実行履歴を表示（Status: Running → Succeeded）
just logs             # stdout を Log Analytics から表示（取り込みに数分遅延あり）
```

## 因果を確かめる実験

「設定を出し入れして結果が変わる」のを体験する。各 `*-demo` / `set-*` は**再デプロイ**で設定を変える。

### A. スケジュールを変える
```powershell
just set-cron "0 */1 * * *"   # 毎時 0 分（UTC）に変更
just executions               # しばらく後、起動頻度が変わるのを確認
just set-cron "*/5 * * * *"   # 5 分ごとに戻す
```
cron は **UTC・5 フィールド**。JST とのズレ（+9h）に注意。

### B. 失敗とリトライを観察する
```powershell
just fail-demo     # FAIL_JOB=true で再デプロイ → 手動起動
just executions    # Status が Failed になり、リトライ回数ぶん試行されたのを確認
just fail-off      # 正常終了に戻す
```
`replicaRetryLimit`（既定 1）を [modules/job.bicep](modules/job.bicep) で増減すると、リトライ回数が変わる。

### C. 1 実行の中で複数レプリカを並列実行する
```powershell
just scale-demo 3 3   # parallelism=3 / replicaCompletionCount=3 で再デプロイ → 起動
just executions       # 1 つの execution の下で 3 レプリカが走るのを確認
```
`parallelism`（同時に走るレプリカ数）と `replicaCompletionCount`（成功とみなすのに必要な成功数）の
関係を体感する。「App のレプリカ＝同時処理量」と「Job のレプリカ＝1 実行を分担する単位」の違い。

## 学習ポイント

### 1. Job は「終了コードで成否が決まる」
App は「生きているか（probe）」で評価されるが、Job は **worker の exit code** が成否。
`exit 0`→Succeeded、`exit 非0`→Failed。バッチ処理の自然な評価軸。

### 2. Schedule と Manual は排他ではない
`triggerType=Schedule` の Job も `az containerapp job start` で手動起動できる。
「普段は定期実行、必要なら今すぐ」が両立する。

### 3. キーレスで ACR から pull
admin user を有効化せず、**User-Assigned MI + AcrPull ロール**で pull する
（auth / k8s トピックで学んだ Managed Identity + RBAC をそのまま適用）。
`registries[].identity` にどの MI を使うか書くのがポイント。

### 4. ログは Environment 経由で Log Analytics へ
個々の Job ではなく **Container Apps Environment** に Log Analytics を紐付けると、
その環境で動く全 Job/App の stdout が集約される。取り込みには数分の遅延がある。

## 発展課題（このプロジェクトの次に）

- **Event トリガー（KEDA）**: Storage Queue にメッセージが入ったら Job が起動・スケールする
  「キュー駆動バッチ」。`automate` トピックの次プロジェクト候補。
- **キーレスの実務化**: ワーカーから `DefaultAzureCredential` で Storage / DB へアクセスし、
  接続文字列を完全に排除（func/k8s の Workload Identity と同じ発想）。
- **手動トリガー専用 Job**: `triggerType=Manual` にして「叩いたときだけ走る」用途と比較。

## 後片付け

```powershell
just destroy
```
