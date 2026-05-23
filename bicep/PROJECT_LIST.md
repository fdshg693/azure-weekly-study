# `bicep` フォルダ直下にある各プロジェクトの説明

1. `apim_learn`
- Bicepを使ったシンプルな CRUD の Function App
- python を利用
- Rest Clientを利用した、 `.http` ファイルでのテストも同梱
- APIM使用
- AOAI使用

2. `vm_command_runner`(3と関連)
- Function App (HTTP Trigger) でホワイトリスト済みコマンドを受け取り、Azure VM 上で実行
- VM への接続は NSG で全拒否し、Azure Run Command (制御プレーン経由) のみで操作
- アイドル時は Timer Trigger が VM を deallocate (課金停止)
- 停止中アクセス時は 202 を返してバックグラウンドで起動
- python / Managed Identity (key-less) ベース
- `/api/run` `/api/status` `/api/start` `/api/stop` `/api/logs` を公開
- `vm_command_web` をデプロイすると Easy Auth (AAD) が前段に被さり、App Service の MI のみが呼び出し可能になる

3. `vm_command_web`(2と関連)
- SvelteKit を App Service (Linux + Node 20, adapter-node) で動かす管理コンソール
- ブラウザは App Service Easy Auth (Entra ID) で認証必須、JS から直接 Function は呼ばない (SSR/サーバルート経由)
- App Service の System-Assigned MI が AAD トークンを取得し Function を Bearer 認証で呼ぶ
- `vm_command_runner` の Function 側 Easy Auth を allowedPrincipals = App Service MI Object ID で固める
- コマンド実行 / 状態確認 / 手動 start・stop / 実行履歴 を画面から操作可能

4. `k8s`
- 記事 `aks_app_build.md` を Bicep + Justfile で実装した「AKS が主役」の最小構成アプリ
- ACR / AKS (application routing addon) / PostgreSQL フレキシブルサーバーを Bicep でデプロイ
- 記事の `--attach-acr` は kubelet マネージド ID への AcrPull ロール付与で再現
- K8s マニフェスト (Deployment / Service / Ingress / HPA / Secret) は `manifests/` に分離、`justfile` で適用
- サンプルアプリ同梱: `api/` (Flask + psycopg, /healthz と /api)、`front/` (nginx 静的ページ)
- ビルドは `az acr build` でクラウド側実行 (手元に Docker 不要)
