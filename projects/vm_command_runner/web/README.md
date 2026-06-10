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

`just` を使うと 1 コマンドずつにまとめられる:

```pwsh
just aad-create-func                              # Function 側 (S2S 用)
just aad-create-web app-vmcmdweb-xxxxxxxx         # App Service 側。引数は予定する App Service 名
# 出力された Web AAD secret は後で 'just set-auth-secret <secret>' で登録
```

素の az で実行する場合:

```bash
FUNC_AAD_APP=$(az ad app create --display-name "vmcmd-func-aad" --sign-in-audience AzureADMyOrg --query appId -o tsv)
az ad app update --id $FUNC_AAD_APP --identifier-uris "api://$FUNC_AAD_APP"

APPSVC_NAME="app-vmcmdweb-xxxxxxxx"
WEB_AAD_APP=$(az ad app create \
  --display-name "vmcmd-web-aad" \
  --sign-in-audience AzureADMyOrg \
  --web-redirect-uris "https://${APPSVC_NAME}.azurewebsites.net/.auth/login/aad/callback" \
  --enable-id-token-issuance true \
  --query appId -o tsv)
WEB_AAD_SECRET=$(az ad app credential reset --id $WEB_AAD_APP --query password -o tsv)
```

### 3. `main.local.bicepparam` を作成

```pwsh
just init-local-param
# main.local.bicepparam を編集して functionAppName, functionAppResourceGroup,
# functionAadClientId, webAadClientId を埋める
```

## デプロイ

### 4. インフラ + Web AAD secret 登録 + SvelteKit デプロイ (just)

```pwsh
just group-create                       # デフォルト: rg-vmcmdweb / japaneast
just deploy-local                       # main.local.bicepparam でデプロイ
just set-auth-secret <web-aad-secret>   # MICROSOFT_PROVIDER_AUTHENTICATION_SECRET を登録
just publish                            # svelte ビルド → zip → az webapp deploy
```

### 4. (代替) 素の az / npm を使う場合

```bash
az group create --name rg-vmcmdweb --location japaneast
az deployment group create \
  --resource-group rg-vmcmdweb \
  --template-file main.bicep \
  --parameters main.local.bicepparam

az webapp config appsettings set \
  --resource-group rg-vmcmdweb \
  --name <bicep 出力された webAppName> \
  --settings MICROSOFT_PROVIDER_AUTHENTICATION_SECRET=$WEB_AAD_SECRET

cd svelte
npm install
npm run build
cp ../svelte/package.json build/ 2>/dev/null || true
cd build && zip -r ../app.zip . && cd ..
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

```pwsh
just local-install   # svelte/ で npm install
az login             # DefaultAzureCredential が az login 済みアカウントを使う
just local-dev       # svelte/ で npm run dev
```

ローカル実行時は `x-ms-client-principal-name` ヘッダが無いため画面右上の user 表示は空になる。Function を叩くトークンは `az login` した個人アカウントで取得されるため、Function 側 Easy Auth の `allowedPrincipals` に自分のユーザー Object ID を追加するか、開発中は Easy Auth を一時的に無効化する。
