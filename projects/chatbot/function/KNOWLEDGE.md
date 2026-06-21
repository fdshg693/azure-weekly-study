# KNOWLEDGE（共有メモ Function）

このプロジェクトで新たに出た用語・概念。チャット本体（`../`）でカバー済みの語
（マネージド ID / DefaultAzureCredential / Entra App Registration / OBO / Key Vault 等）は再掲しない。

## Azure Functions（Node.js v4 プログラミングモデル）
- サーバーレスでイベント駆動のコードを動かす Azure のサービス。今回は HTTP トリガーで REST API を作った。
- **v4 モデル**: `@azure/functions` を `require` し、`app.http("name", { methods, route, handler })` で
  コード側からルートを宣言する方式。旧 v3 の `function.json` ファイルは不要。
- **Consumption（Y1）プラン**: 実行回数・実行時間に対する従量課金。アイドル時はほぼ無料で学習向け。

## Azure Table Storage / `@azure/data-tables`
- 構造化データを安価に大量格納できる NoSQL（キー・バリュー的）ストア。
- **PartitionKey + RowKey** の複合主キー。同一 PartitionKey は同じ物理パーティションに集まり、
  範囲クエリが速い。今回は共有メモなので `PartitionKey="memo"` 固定、`RowKey=メモID`。
- `TableClient` は `DefaultAzureCredential`（MI・キーレス）でも接続文字列（Azurite）でも生成できる。
- **Storage Table Data Contributor**: Table のエンティティ CRUD を許可するデータ平面 RBAC ロール。
  コントロールプレーン（リソース管理）の Contributor とは別物。

## App Service 認証 / EasyAuth（`auth_settings_v2`）
- App Service / Functions に**コードを書かずに**認証を付けられる組み込み機能。
- Entra プロバイダを有効化すると、受信トークンの署名・有効期限・**aud（対象者）**を
  プラットフォームが検証し、通過したリクエストのクレームを **`x-ms-client-principal`**
  （Base64 の JSON）ヘッダーでアプリに渡す。`unauthenticated_action="Return401"` で未認証を弾く。

## app role（アプリロール）とアプリ間認証
- **app role**: App Registration に定義する権限。`allowedMemberTypes=["Application"]` にすると
  **ユーザーではなくアプリ（サービスプリンシパル / マネージド ID）に割り当てられる**。
- 呼び出し側（Web App の MI）にこの role を割り当てると、MI が取得するトークンの
  `roles` クレームに `Memo.ReadWrite` が載る。Function 側はこれを見て認可する。
- **OBO（委任）との違い**: OBO は「サインインしたユーザー本人」の権限で下流を呼ぶ。app role は
  「アプリ自身」の権限。共有データ・バックグラウンド処理はこちらが適切。
- トークン取得は client credentials 相当（`api://<appId>/.default` スコープ）。MI なら
  `DefaultAzureCredential` がこれを透過的に行う（シークレット不要）。

## `x-ms-client-principal` の roles 取り出し
- EasyAuth が渡す principal JSON では、app role は `userRoles` 配列、または
  `claims` 配列内の `typ:"roles"`（あるいは古い `.../claims/role`）として現れる。
  実装では両方を見てから必要ロールの有無を判定している（`src/functions/memos.js`）。
