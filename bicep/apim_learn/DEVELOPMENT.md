# Development Notes

このファイルはローカル実行、コード配布の仕組み、開発時の注意点をまとめたメモです。

## ローカル実行

`justfile` を使う場合:

```powershell
just local-install
just local-start
```

手動で実行する場合:

`python` ディレクトリで依存関係をインストールして起動します。

```powershell
cd python
pip install -r requirements.txt
func start
```

ローカル実行時のベース URL:

```text
http://localhost:7071/api
```

## コード配布の仕組み

`main.bicep` は以下のファイルを読み込みます。

- `python/function_app.py`
- `python/host.json`
- `python/requirements.txt`

その内容を `modules/function-code-deployment.bicep` から Deployment Script に渡し、zip deploy を実行します。これにより、インフラ作成と最小限のアプリ配布を 1 回のデプロイで完了できます。

## APIM と Function App の保護

APIM から Function App への呼び出しでは、内部用の共有シークレットを `x-backend-auth` ヘッダーとして付与します。Function App 側はこのヘッダーを検証し、合わない場合は `401 Unauthorized` を返します。

この共有シークレットは secure パラメータです。未指定時はデプロイ時に自動生成され、固定値が必要な場合だけ `main.local.bicepparam` で上書きします。

## APIM と Azure OpenAI の接続

Azure OpenAI を APIM 配下へ追加する場合は、Bicep で Azure OpenAI 自体を新規作成するのではなく、既存の AOAI エンドポイントと API キーを APIM に渡して別 API として公開します。

- `enableAzureOpenAiApi = true`
- `azureOpenAiEndpoint = 'https://<your-resource>.openai.azure.com'`
- `azureOpenAiApiKey = '<secure-value>'`

APIM 側では AOAI 用の別 Product / Subscription を作り、バックエンドには `api-key` ヘッダーを自動付与します。公開パスは `/aoai` です。

## Git に入れないもの

以下は Git 管理対象外です。

- `main.json`
- `*.local.bicepparam`
- `*.local.http`
- `_scratch*.json`

共通値は `main.bicepparam` に置き、個人用・環境用の値は `main.local.bicepparam` に分離してください。

## 注意事項

- データは `function_app.py` 内のインメモリ辞書に保持しているだけなので永続化されません
- Function App の再起動やスケール時にデータは消えます
- 利用者向け認証は APIM のサブスクリプションキーです
- 本番用途では Key Vault 管理、アクセス制限、Private Endpoint、Entra ID などを検討してください
- `main.json` は Bicep から生成される ARM テンプレートです

## 関連ファイル

- `main.bicep`
- `main.bicepparam`
- `main.local.bicepparam.example`
- `python/function_app.py`
- `test.http`