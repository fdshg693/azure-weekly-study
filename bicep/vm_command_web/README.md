# vm_command_web

SvelteKit on App Service の管理コンソール。既存の [`vm_command_runner`](../vm_command_runner/README.md) の Function を **App Service バックエンドからのみ呼べる** 形に閉じ込め、ブラウザからは Entra ID ログイン経由で操作させる。

## やりたいこと

- ブラウザから VM コマンドの実行 / VM 状態確認 / 手動 start/stop / 履歴閲覧
- Function App は外部から直接叩けない (Easy Auth で App Service の MI のみ許可)

## 構成

```
Browser
  │ Entra ID login (App Service Easy Auth が強制)
  ▼
App Service (Linux + Node 20, SvelteKit/SSR, System-Assigned MI)
  │  ServerRoute (/api/*) のみ Function を呼ぶ。クライアント JS から直接 Function は呼ばない。
  │  Authorization: Bearer <MI が取得した AAD トークン (audience=api://<funcAppId>)>
  ▼
Function App (vm_command_runner, Easy Auth=AAD, allowedPrincipals=App Service の MI Object ID)
  ├─ /api/run
  ├─ /api/status
  ├─ /api/start  /api/stop
  └─ /api/logs
  ▼ MI + Run Command
Azure VM
```

## 事前準備

### 1. `vm_command_runner` のデプロイ

このプロジェクトより先にデプロイしておく。**Function App 名 / RG 名 / Storage Account 名** が必要。

### 2. AAD アプリ登録 2 つを作成

#### (a) Function 側 (サービス間認証用)

```bash
FUNC_AAD_APP=$(az ad app create --display-name "vmcmd-func-aad" --sign-in-audience AzureADMyOrg --query appId -o tsv)
echo "Function AAD clientId: $FUNC_AAD_APP"

# Identifier URI (audience として使う) を登録
az ad app update --id $FUNC_AAD_APP --identifier-uris "api://$FUNC_AAD_APP"
```

#### (b) App Service 側 (ユーザーログイン用)

```bash
APPSVC_NAME="app-vmcmdweb-xxxxxxxx"   # bicep デプロイ後の App Service 名 (先に出力されたものでも OK)
# まず適当な reply URL で作り、デプロイ後に修正でも可
WEB_AAD_APP=$(az ad app create \
  --display-name "vmcmd-web-aad" \
  --sign-in-audience AzureADMyOrg \
  --web-redirect-uris "https://${APPSVC_NAME}.azurewebsites.net/.auth/login/aad/callback" \
  --enable-id-token-issuance true \
  --query appId -o tsv)
echo "Web AAD clientId: $WEB_AAD_APP"

# Easy Auth (Express ではない手動構成) では client secret が必要
WEB_AAD_SECRET=$(az ad app credential reset --id $WEB_AAD_APP --query password -o tsv)
echo "Web AAD secret: $WEB_AAD_SECRET   <- 後で App Service に MICROSOFT_PROVIDER_AUTHENTICATION_SECRET として登録"
```

### 3. `main.local.bicepparam` を作成

```bash
cp main.local.bicepparam.example main.local.bicepparam
# functionAppName, functionAppResourceGroup, functionAadClientId, webAadClientId を埋める
```

## デプロイ

### 4. インフラ

```bash
az group create --name rg-vmcmdweb --location japaneast   # 必要に応じて
az deployment group create \
  --resource-group rg-vmcmdweb \
  --template-file main.bicep \
  --parameters main.local.bicepparam
```

### 5. App Service に Web AAD アプリの client secret を登録

```bash
az webapp config appsettings set \
  --resource-group rg-vmcmdweb \
  --name <bicep 出力された webAppName> \
  --settings MICROSOFT_PROVIDER_AUTHENTICATION_SECRET=$WEB_AAD_SECRET
```

### 6. SvelteKit のビルドとデプロイ

```bash
cd svelte
npm install
npm run build

# build/ 配下と node_modules を含めて zip → デプロイ
cp ../svelte/package.json build/ 2>/dev/null || true   # adapter-node の起動に必要
cd build
zip -r ../app.zip .
cd ..
az webapp deploy \
  --resource-group rg-vmcmdweb \
  --name <bicep 出力された webAppName> \
  --src-path app.zip \
  --type zip
```

> 補足: adapter-node の `build/` は `node build/index.js` で起動可能な単体アプリ。runtime に必要な dependencies は build にバンドルされる。

### 7. アクセス

`https://<webAppName>.azurewebsites.net/` をブラウザで開くと Entra ID ログインに飛ばされ、ログイン後にコンソール画面が表示される。

## セキュリティモデル要点

| 層 | 仕組み |
|---|---|
| ブラウザ → App Service | App Service Easy Auth (AAD) でログイン必須 |
| App Service → Function | App Service の System-Assigned MI が `api://<funcAadClientId>` 宛トークン取得 → Bearer 送付 |
| Function 入口 | Easy Auth (AAD) で audience + `allowedPrincipals.identities` (App Service の MI Object ID) を検証 |
| Function → VM | 既存通り Function の MI で Run Command (制御プレーン経由) |

**Function の Function key は不要**: `function_app.py` の `AuthLevel.ANONYMOUS` に変更済みで、Easy Auth が前段で 401 を返す。

## ローカル開発

```bash
cd svelte
cp .env.example .env
npm install
az login   # DefaultAzureCredential が az login 済みアカウントを使う
npm run dev
```

ローカル実行時は `x-ms-client-principal-name` ヘッダが無いため画面右上の user 表示は空になる。Function を叩くトークンは `az login` した個人アカウントで取得されるため、Function 側 Easy Auth の `allowedPrincipals` に自分のユーザー Object ID を追加するか、開発中は Easy Auth を一時的に無効化する。
