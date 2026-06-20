# KNOWLEDGE — observability で新たに出た用語・概念

これまで（`simple` / `config-rollout` / `workload-identity` / `helm-kustomize`）でカバー済みの語
（Deployment / Service / HPA / probe / namespace / requests・limits など）は繰り返さない。
このプロジェクトで**新しく主役になった**ものだけを書く。

## Container Insights
AKS を **Log Analytics ワークスペース**に紐付けて、コンテナ/Pod/ノードの CPU・メモリ・状態・ログ・
再起動を集める Azure 標準の監視機能。Portal の AKS → **Monitoring → Insights** ブレードで見る。

- 仕組み: クラスタに監視エージェント (DaemonSet) が入り、メトリクス/ログを Log Analytics へ送る。
- 有効化: `az aks enable-addons --addons monitoring`（`--workspace-resource-id` 省略で既定ワークスペースを自動作成）。
- 課金: 主に**ログ/メトリクスの取り込み量**に対して発生（小規模なら軽い）。

## マネージド Prometheus（Azure Monitor managed service for Prometheus）
OSS の Prometheus を**自前運用せず**にメトリクスを集める Azure マネージドサービス。データは
**Azure Monitor ワークスペース**に貯まり、**PromQL**で問い合わせできる。

- 有効化: `az aks update --enable-azure-monitor-metrics`。既定の Azure Monitor ワークスペース・
  データ収集ルール (DCR) などを Azure 側が自動で用意する。
- Container Insights（Log Analytics）とは**別の貯め先**。ログ寄りが Log Analytics、時系列メトリクス寄りが
  Prometheus、と役割が分かれる。

## Azure Managed Grafana
Grafana を**自前で立てない**マネージド版。マネージド Prometheus / Azure Monitor をデータソースに、
Kubernetes の標準ダッシュボード（namespace 別・Pod 別の CPU/メモリ等）をすぐ使える。

- 作成: `az grafana create`（`amg` CLI 拡張が要る）。`--enable-azure-monitor-metrics --grafana-resource-id` で
  AKS 有効化と同時にデータソース登録・ロール割り当てまで Azure がまとめて行う。
- 課金: **インスタンス課金（時間あたり）**。学習後は削除してコストを止めるのが重要。

## 「監視の貯め先」の地図（このプロジェクトの肝）
| 何を | どこに貯まる | どう見る |
|---|---|---|
| ログ・コンテナ状態・再起動 | Log Analytics ワークスペース | Container Insights ブレード |
| 時系列メトリクス | Azure Monitor ワークスペース | PromQL / Managed Grafana |

「**監視を有効化する＝どこかにワークスペースを作って、そこへ送る経路を貼る**」という構造を掴むのが要点。

## HPA のスケール判断を「裏側」から見る
HPA は `kubectl get hpa` の `TARGETS`（現在 CPU% / 目標%）を見て増減を決める。その **CPU% の元データ**が
監視メトリクス。負荷をかけた瞬間の CPU グラフと HPA のレプリカ増加を**同じ時間軸**で並べると、
「HPA がスケールしたのは、このメトリクス上昇を観測したから」という**因果**が一目で分かる。
`kubectl top` / metrics-server の瞬間値に対し、監視は**時系列**で「いつ・どれだけ」を残してくれる点が違い。

## アプリ側の「負荷つまみ」テクニック
監視グラフを意図的に動かすため、観察対象アプリに次のエンドポイントを持たせた。
- `/work?ms=N`: リクエスト中に**同期的に**CPU を焼く → 多重に叩くと Service が全 Pod に分散し平均 CPU↑（HPA 用）。
- `/burn?seconds=N`: **その Pod だけ**をバックグラウンドで焼く → Pod 単位メトリクスの差を見る用。
- `/crash`: プロセスを落として**再起動**を起こす → restartCount/再起動イベントを見る用。
（Python の GIL で 1 スレッドは概ね 1 コア分。HPA 閾値を超えさせるには十分、という割り切り。）
