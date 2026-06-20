# KNOWLEDGE — config-rollout で新たに出た用語・概念

`simple` でカバー済みの語（Deployment / ReplicaSet / Service / Ingress / HPA / Secret / probe / ClusterIP など）は
ここでは繰り返さない。このプロジェクトで**新しく主役になった**ものだけを書く。

## ConfigMap
非機密の設定をキー/値で持つオブジェクト。Secret と違い中身は暗号化も base64 化もされず**平文**で保持される
（＝パスワード等の機密を入れてはいけない）。`envFrom.configMapRef` で Pod に環境変数として丸ごと注入できる。
本プロジェクトでは `app-config`（`APP_MESSAGE` / `FEATURE_GREETING`）として API の挙動を外出ししている。

- **Secret との使い分け**: 機密 = Secret、非機密 = ConfigMap。注入の仕組み（`envFrom`）は同じ。
- **反映タイミングの罠**: `envFrom` 由来の env は **Pod 起動時に固定**される。ConfigMap を更新しても既存 Pod には
  反映されず、`kubectl rollout restart` などで Pod を入れ替える必要がある。
  （ボリュームマウントで配ると遅延反映されるが、本プロジェクトでは env 方式の罠を体感する側を採用。）

## ローリングアップデート（RollingUpdate 戦略）
Deployment のデフォルト更新戦略。古い Pod を一度に全部消さず、新旧を少しずつ入れ替えて無停止更新する。

- **maxSurge**: 望ましいレプリカ数を**超えて**一時的に立ててよい上限（数 or %）。大きいほど速いが余分にリソースを使う。
- **maxUnavailable**: 更新中に同時に**欠けてよい**Pod 数の上限（数 or %）。0 にすると常に全数を維持（その分 surge が要る）。
- **minReadySeconds**: Pod が Ready になってから「安定した」とみなすまでの待ち時間。観察しやすさ・安全側に効く。

## rollout サブコマンド
- `kubectl rollout status`  : 進行中の更新が完了するまで待つ／状態を見る。
- `kubectl rollout history` : 改訂（revision）の履歴を見る。
- `kubectl rollout undo`    : 直前（または指定）の改訂に戻す＝ロールバック。
- `kubectl rollout restart` : イメージは変えずに Pod を作り直す（ConfigMap 変更の反映などに使う）。

## readiness probe が「ロールアウトを止める」働き
readiness probe が新 Pod を Ready にしない限り、ローリングアップデートは次に進まない。
そのため**壊れたイメージを出しても古い Pod が生き残り**、サービスは落ちない（自動で安全側に止まる）。
本プロジェクトの `:v2-bad` は `/healthz` を 500 にしてこの挙動を再現する。

## イメージのビルド引数（Docker `ARG` → `ENV`）
1 つのソース／Dockerfile から、ビルド時の `--build-arg` で挙動の異なるイメージを作るテクニック。
本プロジェクトは `APP_VERSION`（応答に出すバージョン）と `BREAK_HEALTH`（probe を壊すか）を ARG で受け、
`config/api:v1` / `:v2` / `:v2-bad` を作り分けている。`az acr build --build-arg KEY=VALUE` で渡す。

## namespace（名前空間）
同一クラスタ内の論理的な仕切り。リソース名の衝突回避・一覧の見やすさ・後片付け（namespace 削除で一括除去）に効く。
本プロジェクトは `config-rollout` 名前空間に閉じ、`simple`（default 名前空間）と隔離している。
`kubectl ... -n config-rollout` で対象を明示する。

## resources.requests と HPA の関係（補足）
HPA の `averageUtilization`（CPU %）は **`resources.requests.cpu` に対する割合**で評価される。
よって requests を下げると同じ負荷でも使用率（%）が上がり、HPA が早く発火する。
「確保量（requests）」がスケジューリングだけでなくオートスケールの分母でもある、という気づき。
