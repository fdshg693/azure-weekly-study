# automate（自動化）トピック — ユーザーのレベル感と次プロジェクトの目安

このトピックは **Azure 上での「自動化／バッチ実行」** を主役に、`learn/automate/{name}/` の
各プロジェクトで段階的に学ぶ。共通方針はリポジトリ全体と同じ「**一般概念／最小構成 → 実装 →
設定を出し入れして因果を確かめる**」「**構築・実行はユーザー自身、AI は Azure 上で実行しない**」。

軸は **「常駐させない実行モデル」**。func（コードで書くサーバーレス）・logicapps（繋ぐワークフロー）・
AKS（コンテナを常駐させる）との対比で、「**コンテナを起動して仕事をして終了させる**」を扱う。

## 使用技術

- 環境構築は **Bicep**（`main.bicep` + `modules/` で役割分割）。
- ワーカーは用途に応じた言語のコンテナ（最初は Python 標準ライブラリのみ）。
- イメージは **ACR Tasks（`az acr build`）** でクラウド側ビルド（ローカル Docker 不要）。
- コマンド集約は `justfile`（pwsh）。
- ACR からの pull は **User-Assigned Managed Identity + AcrPull**（auth/k8s の RBAC を踏襲）。

## プロジェクト一覧

### `simple` — Container Apps Job（Schedule トリガー）が主役
`./simple`

automate の最初のプロジェクト。**Azure Container Apps Jobs** で「起動 → 仕事 → 終了」が 1 回で
完結する Job を **cron（Schedule トリガー）で定期実行**し、`az containerapp job start` で手動起動も
併用する。Bicep で Log Analytics / Container Apps Environment / ACR / UAMI(+AcrPull) / Job を作り、
ワーカーは `worker.py`（標準ライブラリのみ、終了コードで成否を表す）。
**因果を確かめる実験**: cron 差し替え（`set-cron`、UTC・5 フィールド）で起動頻度が変わる／
`FAIL_JOB=true`（`fail-demo`）で **Failed + `replicaRetryLimit` ぶんのリトライ**を観察／
`parallelism`・`replicaCompletionCount`（`scale-demo`）で **1 execution 内の複数 replica** を観察。
肝は **App（常駐・probe で評価）と Job（終了 ・終了コードで評価）の違い**、
**execution と replica の関係**、**Environment に紐付けた Log Analytics へ stdout が集約される**こと。

### `runbook` — Azure Automation の runbook で VM を起動/停止する
`./runbook`

automate の 2 つめ。**Azure Automation** を主役に、`simple`(自作コンテナを起動して終了)と対比して
**「イメージを持たず、Azure 提供の PowerShell ランタイムで runbook を走らせ、Automation Account 自身の
system-assigned MI で Azure リソース(VM)を操作する」** モデルを学ぶ。`vm/simple` の「deallocate で課金が
止まる」を runbook に自動化させる位置づけ。Bicep で Automation Account(+MI) / **Reader + Virtual Machine
Contributor**(RG スコープ) / **Automation 変数**(共有アセット) / **空ドラフトの runbook** を作り、本文は
`az automation runbook replace-content`+`publish` で後からアップロード（simple の `az acr build` に相当）。
ワーカーは `Manage-VMPower.ps1`（`Connect-AzAccount -Identity` → `Start/Stop-AzVM`）。
**因果を確かめる実験**: `revoke-vmcontrib`/`grant-vmcontrib` で **認証(MI)と認可(RBAC)の分離**を体感
（Reader だけだと読めても Start/Stop は 403）／`set-var` で **Automation 変数**を変えコードを書き換えず挙動を変える／
`fail-demo` で Failed + Error ストリーム／`schedule`・`set-tz` で **タイムゾーン付きスケジュール**（Container Apps の
UTC 固定 cron との対比）。スケジュールは immutable なので通常 deploy には含めず専用レシピで一度だけ作る。

## 学習済みの概念

- Container Apps の **App / Job** の違い（常駐 vs 起動して終了、評価軸＝probe vs 終了コード）
- **Container Apps Environment**（App/Job の実行境界・ログ出力先の単位）
- **Job のトリガー種別**（Manual / Schedule / Event）と、Schedule と Manual の併用
- **Schedule トリガー**の cron（5 フィールド・**UTC**）
- **execution と replica**、`parallelism` / `replicaCompletionCount` / `replicaRetryLimit` / `replicaTimeout`
- **MI + AcrPull によるキーレス pull**（`registries[].identity`）を Container Apps に適用
- **ContainerAppConsoleLogs_CL** での stdout 確認（取り込み遅延あり）、`az containerapp job execution list`

### Azure Automation（`runbook` プロジェクト）

- **Automation Account / Runbook / ジョブ**の関係。runbook はイメージ不要で **Azure 提供ランタイム**で走る。
- **ドラフトと発行(publish)**、Bicep の `draft: {}`（空 runbook）＋ CLI で本文アップロードという二段構え。
- **`Connect-AzAccount -Identity`**: アカウントの system-assigned MI として Azure を操作する（「Azure が Azure を操る」）。
- **ロールで操作可否が変わる**: Reader(読む) と Virtual Machine Contributor(Start/Stop)。認証と認可の分離を再確認。
- **Automation 変数（共有アセット）**: `Get-AutomationVariable`、value は JSON エンコード。設定とコードの分離。
- **タイムゾーン付きスケジュール** と **jobSchedule**（schedule↔runbook 紐付け）。スケジュールは immutable。
- ジョブの **Output ストリーム**を `az rest .../jobs/{name}/output` でテキスト取得（出力取得用 CLI が無いため）。

## まだ触れていない主要概念（次プロジェクトの候補）

- **Event トリガー（KEDA）**: Storage Queue / Service Bus 駆動のキュー消費バッチ（Container Apps Job の自然な次の一手）。
- **triggerType=Manual 専用 Job**: 「叩いたときだけ走る」用途との対比。
- **ワーカーからのキーレスアクセス**: `DefaultAzureCredential` で Storage/DB へ（接続文字列の排除）。
- **Automation の発展**: Webhook トリガー、Hybrid Runbook Worker、Python runbook、複数サブスク横断。
- **他の自動化サービスとの対比**: Logic Apps（logicapps トピック）/ Functions Timer トリガー（func トピック）/
  Azure Batch との使い分け。
- **失敗時の通知・アラート**（Log Analytics / Monitor アラート）。
