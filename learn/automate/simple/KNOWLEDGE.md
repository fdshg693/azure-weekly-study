# KNOWLEDGE — automate/simple で新たに出た用語・概念

このトピック（automate）で初めて登場した語をまとめる。Managed Identity / RBAC / AcrPull /
ACR / `az acr build` など、auth・k8s・func トピックで既出の語は再掲しない。

## Azure Container Apps Jobs（コンテナジョブ）

- **Job vs App**: Container Apps には常駐型の **App** と、起動して終了する **Job** がある。
  Job は「1 回の実行で処理を完了させて終わる」モデルで、バッチ・定期処理・キュー消費向き。
  成否は**コンテナの終了コード**で決まる（`0`=Succeeded、非 0=Failed）。
- **Container Apps Environment（managedEnvironments）**: App / Job が同居する実行環境の境界。
  ネットワークやログ出力先（Log Analytics）はこの環境単位で設定する。
- **execution（実行）と replica（レプリカ）**: Job を 1 回起動するのが 1 つの execution。
  その execution は 1 個以上の replica（コンテナ）で構成される。
  - `parallelism`: 1 execution で**同時に走らせる** replica 数。
  - `replicaCompletionCount`: その execution を成功とみなすのに**成功が必要な** replica 数。
  - App の「レプリカ＝同時処理量（スケール）」とは意味が異なる点に注意。

## トリガーの種類（triggerType）

- **Manual**: `az containerapp job start` で叩いたときだけ実行。
- **Schedule**: cron 式で定期実行。**5 フィールド cron・UTC** で指定する（JST は +9h ズレ）。
  Schedule の Job も Manual 起動を併用できる（排他ではない）。
- **Event**: KEDA スケーラ（Storage Queue / Service Bus 等）でイベント駆動。本プロジェクト未使用。

## 信頼性・実行制御のパラメータ

- **replicaRetryLimit**: replica が失敗（非 0 終了）したときのリトライ回数。
- **replicaTimeout**: 1 replica の最大実行秒数。超えると打ち切られる。
- **scheduleTriggerConfig**: `cronExpression` / `parallelism` / `replicaCompletionCount` をまとめる設定。

## ツール・運用

- **`az containerapp job start`**: Job を手動起動する。
- **`az containerapp job execution list`**: 実行履歴（execution 単位）と Status を一覧する。
- **ContainerAppConsoleLogs_CL**: Container Apps の stdout が入る Log Analytics のテーブル。
  `ContainerAppName_s` で Job 名を絞り込める。取り込みに数分の遅延がある。
- **`registries[].identity`**: Job がレジストリにアクセスする際にどの Managed Identity を使うかの指定。
  admin user を使わずキーレスで pull するための要。
