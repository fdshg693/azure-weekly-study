# Azure Automation の runbook で VM を起動/停止するプロジェクト

`automate` トピックの 2 つめのプロジェクト。**Azure Automation** を主役に、
**「runbook(スクリプト)を Azure のマネージド実行環境で走らせ、Automation Account 自身の
マネージド ID で Azure リソース(VM)を操作する」** 自動化を体験する。

`vm/simple` で学んだ「VM を `deallocate` すると課金が止まる」を、ここでは
**人手ではなく runbook に自動で行わせる**。`simple`(Container Apps Job)が
「自作コンテナを起動して終了」だったのに対し、こちらは
**「コンテナもイメージも持たず、Azure が用意した PowerShell ランタイムでスクリプトを走らせる」** モデル。

## simple (Container Apps Job) との対比（このプロジェクトの肝）

| | Container Apps **Job** (simple) | Azure Automation **Runbook** (このプロジェクト) |
| --- | --- | --- |
| 実行する中身 | 自作コンテナイメージ (ACR に push) | スクリプト(runbook)をアップロード・発行 |
| ランタイム | 自分で組む (Dockerfile) | Azure 提供 (PowerShell 5.1 / 7.x / Python) |
| 何をするのが得意か | 任意の処理を「起動して終了」 | **Azure を Azure 自身が操作** (VM 起動停止・タグ付け等) |
| 認証 | UAMI + AcrPull で **pull** するための ID | アカウントの MI で **Azure を操作** する ID |
| スケジュール | cron 5 フィールド・**UTC 固定** | **タイムゾーン指定可**・頻度(Day/Hour/…)で指定 |
| 設定の外出し | env / Bicep パラメータ | **Automation 変数(共有アセット)** |
| 成否 | コンテナの終了コード | ジョブの Status(Completed/Failed)・例外 |

## 仕組み

```
                  ┌─────────────────────────────────────────────┐
                  │  Automation Account (aa-rbvm)               │
   schedule       │   system-assigned Managed Identity ●        │
   (任意/TZ可)    │   ┌───────────────────────────────────────┐ │
   ─────────────▶ │   │ Runbook: Manage-VMPower (PowerShell)  │ │
                  │   │  Connect-AzAccount -Identity          │ │
   az runbook     │   │  → Start-AzVM / Stop-AzVM             │ │
   start ───────▶ │   └───────────────────────────────────────┘ │
   (手動)         │   Automation 変数: DefaultAction /          │
                  │     TargetVMName / TargetVMResourceGroup    │
                  └──────────────────●──────────────────────────┘
                                     │ MI が RBAC で操作
                       Reader + Virtual Machine Contributor (RG スコープ)
                                     ▼
                         対象 VM (vm-rbtarget, B1s) ── Start / Deallocate
```

- runbook は **手動起動**(`just start-vm` / `just stop-vm`)でも、**スケジュール**でも走る。
- 手動起動時は引数(`Action` 等)を渡せる。スケジュール実行は引数が無いので、
  代わりに **Automation 変数** から設定を読む(= 設定とコードの分離)。
- MI に付けた **ロール**で「できること」が決まる。Reader だけだと電源状態は読めても Start/Stop は失敗する。

## 作られるもの

- リソースグループ（`rg-automate-runbook`）
- Automation Account（`aa-rbvm` / Basic / **system-assigned MI** 有効）
- ロール割り当て（RG スコープ）: MI に **Reader** と **Virtual Machine Contributor**
- Automation 変数 3 つ: `DefaultAction`(=Stop) / `TargetVMName` / `TargetVMResourceGroup`
- Runbook（`Manage-VMPower` / PowerShell / 最初は中身が空）
- （`just vm-create` で）操作対象 VM（`vm-rbtarget` / B1s / Public IP 無し）
- （`just schedule` で任意）スケジュール + jobSchedule

## ファイル

| ファイル | 役割 |
| --- | --- |
| [main.bicep](main.bicep) | 全体のオーケストレーション（account + runbook モジュール） |
| [main.bicepparam](main.bicepparam) | 既定パラメータ |
| [modules/account.bicep](modules/account.bicep) | Automation Account / MI / Reader + VM Contributor / 共有変数 |
| [modules/runbook.bicep](modules/runbook.bicep) | **Runbook 本体**（空ドラフト）＋任意のスケジュール/jobSchedule |
| [runbooks/Manage-VMPower.ps1](runbooks/Manage-VMPower.ps1) | runbook の本文（MI で認証 → VM を Start/Stop） |
| [justfile](justfile) | デプロイ・本文アップロード・手動起動・ジョブ確認・各種因果実験 |

## 使い方

### 前提
- `az login` 済み。**RG にロール割り当てを作るため、デプロイ実行者は Owner か
  User Access Administrator 相当**が必要（MI に Reader/VM Contributor を付与するため）。
- `just` がインストール済み。
- `az automation` 拡張は初回コマンドで自動インストールされる（`az containerapp` と同様）。
- 本文アップロードは `az automation runbook replace-content` を使うのでローカル PowerShell 実行環境は不要。

### 1. デプロイ & runbook 本文アップロード

```powershell
az login
just group-create
just up          # = deploy(Bicep) → upload(runbook 本文を発行)
just outputs     # アカウント名 / Runbook 名 / principalId / 対象 VM を確認
```

### 2. 操作対象の VM を作る

```powershell
just vm-create   # B1s VM を作成 (start/stop の的)。数分かかる
just vm-state    # 現在の電源状態 (VM running)
```

### 3. runbook で VM を止める / 起こす

```powershell
just stop-vm     # runbook を起動。ジョブ名が表示される
just jobs        # ジョブ一覧で Status を確認 (New → Running → Completed)
just job-output <ジョブ名>   # runbook の Write-Output を表示 (power state の前後が見える)
just vm-state    # VM deallocated に変わったことを確認

just start-vm    # 起こす
just vm-state    # VM running に戻る
```

> ジョブは起動直後は `New`/`Activating`。`Completed` まで数十秒〜数分。
> `just jobs` で Status を確認してから `just job-output` を見るとよい。

## 因果を確かめる実験

### A. 認可(RBAC)を出し入れする — 認証と認可の分離
```powershell
just revoke-vmcontrib   # MI から Virtual Machine Contributor を外す
just stop-vm            # 起動はするが…
just job-output <ジョブ名>   # Stop-AzVM が 403(Authorization 失敗)になるのが見える
just status-run         # 一方 Status(読み取り)は Reader だけで通る
just grant-vmcontrib    # 付け直すと再び Stop できる
```
**認証(MI として Azure にサインインできる)と認可(その ID が VM を操作してよいか)は別**、
という `auth`/`k8s` で繰り返してきたテーマを Automation でも体感する。

### B. 共有アセット(Automation 変数)を変える — 設定とコードの分離
```powershell
just show-vars                 # 変数の一覧と値
just set-var DefaultAction Start   # スケジュール/引数なし実行の既定を Start に
just status-run                # 引数を渡さず起動 → 変数の値が使われるのを確認
just set-var DefaultAction Stop
```
runbook の本文を一切書き換えずに、**変数を変えるだけで挙動が変わる**。

### C. 失敗とエラーストリームを見る
```powershell
just fail-demo          # Stop した上で最後に例外 → ジョブが Failed に
just jobs               # Status=Failed
just job-output <ジョブ名>   # Output に処理ログ、例外でエラーになった様子
```

### D. スケジュール（タイムゾーン）を試す — 任意
```powershell
just schedule                       # 毎日(既定 Tokyo Standard Time)実行する jobSchedule を作る
just set-tz "Etc/UTC"               # タイムゾーンを変えて作り直す
just set-tz "Tokyo Standard Time"   # 戻す
```
Container Apps Job の cron が **UTC 固定**だったのに対し、Automation のスケジュールは
**タイムゾーンを指定できる**。スケジュール実行は引数が無いので **Automation 変数**を参照する
（既定 `DefaultAction=Stop` なので「夜間に止める」のような運用になる）。

> Automation のスケジュールは作成後に頻度/開始時刻をほぼ変更できない（immutable）。
> そのため通常の `deploy` には含めず、`just schedule` で一度だけ作る設計にしている。
> 変更したいときは `just set-tz`（既存を消して作り直す）を使う。

## 学習ポイント

### 1. runbook は「イメージ無しで Azure を操作する」
コンテナを組まず、Azure 提供の PowerShell ランタイムでスクリプトが走る。
`Connect-AzAccount -Identity` で **Automation Account の MI** としてサインインし、
`Start-AzVM`/`Stop-AzVM` で Azure を操作する。「Azure が Azure を操る」自動化の形。

### 2. ロールが「できること」を決める
MI は常に同じ(認証は変わらない)。Reader を外せば読めず、VM Contributor を外せば操作できない。
ロールの付け外しでジョブの成否が変わる = **認可は実行時に効く**。

### 3. 設定はコードの外（共有アセット）に
手動起動は引数、スケジュール実行は **Automation 変数**。同じ runbook が文脈に応じて
設定の出どころを変える。変数を書き換えるだけで挙動が変わる。

### 4. スケジュールはタイムゾーンを持てる
cron(UTC)とは別の「いつ走るか」の指定方法。jobSchedule が「どの schedule で
どの runbook を回すか」を紐づける。

## トラブルシュート

- **`Connect-AzAccount`/`Get-AzVM` が "コマンドが見つからない"**: Az モジュール未導入。
  Automation Account → [モジュール] で `Az.Accounts` と `Az.Compute` をインポートする
  （新しいアカウントは既定で入っているが、無ければ手動で追加）。
- **`replace-content` で 404**: `just deploy` で runbook（空）がまだ作られていない。先に `just up`。
- **ロール割り当てのデプロイで権限エラー**: 実行者に RG への Owner / User Access Administrator が無い。
- **stop-vm が 403**: MI に Virtual Machine Contributor が無い（実験 A の状態）。`just grant-vmcontrib`。

## 発展課題（このプロジェクトの次に）

- **Webhook トリガー**: runbook を HTTP POST で外部から起動する。
- **Hybrid Runbook Worker**: オンプレ/別クラウド上で runbook を実行する。
- **Python runbook**: 同じ操作を Python 3 で書き、MI トークン取得・SDK 利用の違いを比較。
- **キーレスの実務化**: 複数サブスクリプション横断や、対象 VM の動的列挙（タグで絞り込み）。

## 後片付け

```powershell
just destroy     # RG ごと削除 (Automation Account も VM もまとめて消える)
```
