# KNOWLEDGE — helm-kustomize で新しく出た用語・概念

`simple` / `config-rollout` / `workload-identity` でカバー済みの語（Deployment・Service・Ingress・HPA・
ConfigMap・namespace・probe・ACR・rollout など）は再掲しない。ここはテンプレート化に固有のものだけ。

## テンプレート化全般

- **マニフェストのテンプレート化**: 環境ごとに変わる値（イメージ・台数・リソース・設定）を素の YAML に
  直書きせず、共通の土台 + 差分という形に分離すること。`__ACR_LOGIN_SERVER__` の文字列置換（sed）からの脱却が動機。
- **環境差分（dev / prod）**: 同じアプリを「最小構成の検証用（dev）」「冗長・自動スケールの本番相当（prod）」に
  構成し分ける。本章では replicas・resources・HPA 有無・設定値・Ingress host が差分。

## Kustomize

- **base / overlay**: `base` は全環境共通の素マニフェスト集合。`overlays/<env>` が base を取り込み（`resources: [../../base]`）、
  **差分だけ**を足す。テンプレート言語を持たず「素の YAML をマージ・変換」するのが Helm との最大の違い。
- **kustomization.yaml**: そのディレクトリで「何を取り込み（resources）、何を変換するか（transformers）」を宣言するファイル。
- **strategic merge patch**: 同じ `kind`＋`name`（＋コンテナは `name`）を持つ部分 YAML を重ねると、その場所だけが
  上書きマージされる。本章の `config-patch.yaml` / `resources-patch.yaml` がこれ。
- **JSON6902 patch**: `op: replace` などで「パス指定のピンポイント書き換え」をする方式。本章では Ingress の
  `/spec/rules/0/host` を dev/prod で差し替えるのに使用。
- **transformer**: kustomization の宣言で機械的に全体を書き換える仕組み。本章で使ったもの:
  - **images transformer**: コンテナの記号名（`app-api`）を実レジストリ・タグ（`newName`/`newTag`）へ変換。
    `__ACR__` の sed を構造的に置き換える主役。
  - **replicas transformer**: 指定 Deployment の `replicas` を上書き（prod を 3 に）。
  - **namespace transformer**: overlay 配下の全リソースに namespace を付与。
  - **labels**: 全リソースに共通ラベルを付与。
- **`kustomize edit set image`**: kustomization.yaml の images エントリを CLI で書き換えるコマンド。
  CI/スクリプトから実イメージを注入する正攻法（手で YAML を sed しない）。
- **`kubectl kustomize <dir>` / `kubectl apply -k <dir>` / `kubectl diff -k <dir>`**: レンダリング / 適用 /
  クラスタ実体との差分。`-k` は kubectl 内蔵 Kustomize を使う。

## Helm

- **chart**: テンプレート + 既定値（values）+ メタ情報（Chart.yaml）を 1 パッケージにまとめたもの。
- **Chart.yaml**: チャートの名前・`version`（パッケージの版）・`appVersion`（中のアプリの版）。
- **values.yaml / values-dev.yaml / values-prod.yaml**: テンプレートに差し込む値。`-f`（`--values`）で
  後勝ちに重ねる（base → 環境）。Kustomize の base / overlay に対応する。
- **テンプレート（Go template）**: `{{ .Values.xxx }}` で値を埋め、`{{- if }}` で条件生成、`{{ include }}` で
  部分テンプレート（`_helpers.tpl`）を再利用。本章では「prod だけ HPA を生成」を `if .Values.hpa.enabled` で表現。
- **`_helpers.tpl` / `define` / `include`**: 共通の式（イメージ参照の組み立てなど）を名前付きテンプレートにして使い回す。
- **`--set key=value`**: コマンドラインで values を上書き。本章では実 ACR を `--set image.registry=<ACR>` で注入。
- **release**: クラスタに入れた chart のインスタンス（`app-dev` / `app-prod`）。Helm は**リリースを記録**するので
  `helm list` / `helm status` / `helm get values` / `helm rollback` / `helm uninstall` が使える（Kustomize には無い概念）。
- **`helm template`（生成のみ）/ `helm upgrade --install`（無ければ install・あれば upgrade）**:
  前者はクラスタに触れずレンダリングだけ、後者が冪等なデプロイ。

## Kustomize vs Helm（要点）

- 同じ「テンプレート化・環境差分」という問題を、**マージ/変換（Kustomize）** と **テンプレート言語+値（Helm）**
  という別アプローチで解く。小さな差分には Kustomize が軽く、条件分岐や配布・リリース管理が要るなら Helm が強い。
