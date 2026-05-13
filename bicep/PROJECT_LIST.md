# `bicep` フォルダ直下にある各プロジェクトの説明

1. `apim_learn`
- Bicepを使ったシンプルな CRUD の Function App
- python を利用
- Rest Clientを利用した、 `.http` ファイルでのテストも同梱
- APIM使用
- AOAI使用

2. `vm_command_runner`
- Function App (HTTP Trigger) でホワイトリスト済みコマンドを受け取り、Azure VM 上で実行
- VM への接続は NSG で全拒否し、Azure Run Command (制御プレーン経由) のみで操作
- アイドル時は Timer Trigger が VM を deallocate (課金停止)
- 停止中アクセス時は 202 を返してバックグラウンドで起動
- python / Managed Identity (key-less) ベース
