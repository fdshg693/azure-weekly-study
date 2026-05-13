# vm_command_runner

シンプルな「Function 経由で VM にホワイトリスト済みコマンドを実行させる」プロジェクト。

## やりたいこと

- HTTP リクエストでコマンド名 (alias) を受け取る
- ホワイトリストに含まれる場合のみ、Azure VM 上で実行
- VM はアイドル時に自動 deallocate (課金停止)
- 停止中にアクセスが来たら **202 を返し、バックグラウンドで起動を試みる**

## 構成

```
Client
  │  POST /api/run { "command": "uptime" }
  ▼
Function App (Linux EP1, Python 3.11, System-Assigned MI)
  ├─ whitelist 検証
  ├─ VM 電源状態を取得 (instance_view)
  │    ├─ running    → Run Command 実行 → 結果を返す (200)
  │    └─ それ以外   → begin_start を発火 → 202 を返す
  ├─ Table "vmstate" に lastAccessUtc を upsert
  └─ Timer (5min) が idle 判定 → begin_deallocate

Azure VM (Ubuntu 22.04, Standard_B1s, NSG 全 inbound 拒否)
  └─ Azure Run Command 拡張 (制御プレーン経由) からのみ操作
```

## セキュリティモデル

- **VM への直接接続は不可**: NSG ですべての inbound を Deny。SSH 鍵は仕様上必須なので登録しているだけで、到達不可。
- **コマンド実行は Azure 制御プレーン経由 (Run Command)**: Function MI → ARM → VM Agent。VM 側にネットワークサーバーを置かない。
- **コマンドインジェクション対策**: ホワイトリストは alias → 固定シェル文字列のマップ。**ユーザー入力をシェルに渡さない**設計。
- **認可**: Function MI に `Virtual Machine Contributor` を VM スコープで付与。

## デプロイ

### 1. 前提

- Azure CLI (`az login` 済み)
- リソースグループ作成済み
- Azure Functions Core Tools (`func`)
- SSH 公開鍵 (`~/.ssh/id_rsa.pub` など)

### 2. パラメータの準備

```bash
cp main.local.bicepparam.example main.local.bicepparam
# main.local.bicepparam を編集して vmAdminSshPublicKey を実際の鍵に差し替え
```

### 3. インフラのデプロイ

```bash
az deployment group create \
  --resource-group <RG名> \
  --template-file main.bicep \
  --parameters main.local.bicepparam
```

### 4. Function コードのデプロイ

```bash
cd python
func azure functionapp publish <デプロイで出力された functionAppName>
```

## 使い方

`test.http` を VS Code REST Client などで開き、`@functionAppName` と `@functionKey` を埋めて実行。

```http
POST https://<func>.azurewebsites.net/api/run?code=<key>
Content-Type: application/json

{ "command": "uptime" }
```

### 許可されているコマンド (alias)

| alias | 実行内容 |
|---|---|
| `whoami` | `whoami` |
| `uptime` | `uptime` |
| `df` | `df -h` |
| `free` | `free -h` |
| `uname` | `uname -a` |
| `date` | `date -u` |
| `hostname` | `hostname` |
| `os-release` | `cat /etc/os-release` |

新しいコマンドを追加するには [python/function_app.py](python/function_app.py) の `COMMAND_WHITELIST` を編集して再デプロイ。

## レスポンス

| コード | 意味 |
|---|---|
| 200 | 実行成功。`outputs` に Run Command の結果が入る |
| 202 | VM が停止中だったため起動を開始。1〜2分後に再試行 |
| 400 | JSON 不正、または whitelist にない command |
| 503 | VM の起動に失敗 |

## 注意点

- **初回 Run Command のオーバーヘッド**: 起動直後は agent の準備があり、1回目の実行が遅いことがある。
- **EP1 プランの常時課金**: Function App 側は時間課金。安く済ませたいなら Consumption (Y1) に変更も可だが、その場合 `AzureWebJobsStorage` を identity-based ではなく接続文字列方式に戻す必要がある。
- **Timer 粒度**: 5分間隔で deallocate を判定。`IDLE_MINUTES_BEFORE_STOP` (デフォルト10分) を超えたら停止。
