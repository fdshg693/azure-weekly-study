# KNOWLEDGE — automate/runbook で新たに出た用語・概念

`simple`(Container Apps Job) で既出の語（Job/App、execution/replica、MI+RBAC、
スケジュール実行一般）は再掲しない。ここでは **Azure Automation** 固有の語をまとめる。

## Azure Automation の構成要素

- **Automation Account**: runbook・スケジュール・共有アセットを束ねる入れ物。
  ここに **system-assigned マネージド ID** を持たせると、runbook がその ID として
  Azure を操作できる。SKU は `Free` / `Basic`。
- **Runbook**: Automation 上で走らせるスクリプト。種別(`runbookType`)は
  `PowerShell`(5.1) / `PowerShell72` / `Python3` / `GraphPowerShell` など。
  実行ランタイムは **Azure 提供**で、コンテナイメージを自分で用意しない点が Job と対照的。
- **ドラフトと発行(publish)**: runbook には「ドラフト(編集中)」と「発行済み」がある。
  本文を `replace-content` でドラフトに入れ、`publish` して初めて実行対象になる。
  Bicep では `draft: {}` で**中身が空の runbook** だけ作れる（本文は後から CLI でアップロード）。
- **ジョブ(job)**: runbook を 1 回実行した単位。Status は `New`→`Activating`→`Running`→
  `Completed`/`Failed`/`Suspended`。Job の **Output ストリーム**に `Write-Output` が入る。
  （他に Error / Warning / Verbose ストリームがある。）

## マネージド ID で「Azure を操作する」

- **`Connect-AzAccount -Identity`**: runbook の中で Automation Account の
  system-assigned MI として Azure にサインインする。鍵も接続文字列も使わない。
- 認証(MI として入れる)と**認可(RBAC ロール)は別物**。
  - `Reader`: VM の電源状態を読む程度。
  - `Virtual Machine Contributor`: VM の Start/Stop(deallocate) など操作。
  ロールを外すと、認証は通るのに操作だけ 403 になる。

## 共有アセット（Shared Resources）

- **Automation 変数(variables)**: コードの外に置く設定値。runbook 内では
  `Get-AutomationVariable -Name '...'` で読む（Automation サンドボックス内専用の内部コマンド）。
  手動起動の引数が無いスケジュール実行で特に有用。
  - **ハマりどころ**: 変数の `value` は **JSON エンコード**が必要。文字列なら
    クオート込みで `"Stop"` のように格納する（Bicep では `value: '"${x}"'`）。
- （他の共有アセット: 資格情報 Credentials / 接続 Connections / 証明書 Certificates /
  モジュール Modules。本プロジェクトでは変数のみ使用。）

## スケジュール

- **schedule**: 「いつ走らせるか」。`frequency`(Day/Hour/Week/Minute/Month/OneTime)・
  `interval`・`startTime`(**必須・未来**)・**`timeZone`** を持つ。
  Container Apps Job の cron が **UTC 固定**なのに対し、**タイムゾーンを指定できる**のが特徴。
  - 作成後は頻度/開始時刻をほぼ**変更不可(immutable)**。変えるときは作り直す。
  - Bicep の `startTime` 既定は `dateTimeAdd(utcNow(), 'PT1H')`。`utcNow()` は
    **パラメータ既定値でのみ**使える関数。
- **jobSchedule**: 「どの schedule で、どの runbook を走らせるか」の紐付け。名前は GUID。
  引数を渡さなければ、スケジュール実行は Automation 変数を参照する。

## ツール・運用

- **`az automation runbook replace-content --content @file`**: runbook 本文(ドラフト)を差し替える。
- **`az automation runbook publish`**: ドラフトを発行する。
- **`az automation runbook start --parameters K=V ...`**: 手動起動。ジョブを返す。
- **`az automation job list` / `job show`**: ジョブ一覧・詳細(Status)。
  - 出力ストリーム取得用の CLI は無いので、Output は **`az rest`** で
    `.../jobs/{name}/output?api-version=...` を GET してテキストで取る。
- **`az vm get-instance-view ... PowerState/*`**: VM の電源状態（`running`/`deallocated`）を確認。

## Container Apps Job との使い分け（automate トピックの軸）

- **自作の任意処理を起動して終了**したい → Container Apps Job（イメージを持ち込む）。
- **Azure リソースの運用操作を、Azure の ID で**やりたい → Azure Automation runbook
  （ランタイム込みで Azure が用意、MI で他リソースを操作、タイムゾーン付きスケジュール）。
