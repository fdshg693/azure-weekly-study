# Azure Storage の学習

Azure Storage Account（主に Blob）を中心に、**公開範囲の制御**と**ネットワーク的な閉域化**を、
プロジェクトごとにサブフォルダで分割して学ぶ。
各プロジェクトは「**最小構成で構築 → 実際にアクセスして、許可されるパス／拒否されるパスを確かめる**」
という、このリポジトリ共通の方針に従う。構築・実行はユーザー自身が行い、AI が Azure 上で実行することはない。

## 使用技術

- 環境構築は **Terraform（`azurerm ~> 3.0`）**（func と同じく Terraform 主体）。
- コマンドの集約は `justfile`（simple）または `terraform` 直叩き（private_endpoint）。
- 動作確認は Azure CLI（`az storage blob ...`）／`curl`／VM からの `nslookup` 等。

## プロジェクト一覧

### simple

`./simple`

`storage` の入口。Storage Account の **静的 Web サイトホスティング**を使い、`$web` コンテナに置いた
`index.html` / `error.html` **だけ**を匿名公開する。核心は **「それ以外のファイルが絶対に公開されない」
ことを 2 段構えで担保**すること:(1) 静的 Web サイトの専用エンドポイント（`*.z.web.core.windows.net`）は
`$web` の中身しか配信しない、(2) `allow_nested_items_to_be_public = false` で Blob エンドポイントからの
匿名アクセス自体を Storage Account レベルで禁止（後から手作業でコンテナを公開しようとしても拒否される）。
private コンテナに置いた `sample.txt` は **SAS トークンを発行しない限り誰からもアクセスできない**ことを、
`data.azurerm_storage_account_sas`（読み取り専用 / HTTPS / 24h）で確かめる。

### private_endpoint

`./private_endpoint`

`storage` の 2 つ目。`simple` が「公開エンドポイント上での公開範囲制御」だったのに対し、こちらは
**Private Endpoint による閉域化**。VNet ＋ サブネット（PE 用 / VM 用）＋ Blob サービスへの Private Endpoint
＋ Private DNS Zone（`privatelink.blob.core.windows.net`）を作り、Storage の
**`public_network_access_enabled = false`** でパブリック経路を塞ぐ。テスト用 Linux VM（任意）を同じ VNet に置き、
VM から `nslookup` で **ストレージ FQDN がプライベート IP（10.0.1.x）に解決される**こと・`curl` で疎通すること、
逆に **インターネット（ローカル PC）からは到達できない**ことを対比して確かめる。Private DNS Zone が
名前解決を private IP に向ける役割を担う点が肝。コスト（PE / Public IP / VM）にも README で言及。

## 学習した概念

- 静的 Web サイトホスティング（`$web` コンテナ／専用 Web エンドポイント）
- Storage の公開制御フラグ（`allow_nested_items_to_be_public` / `public_network_access_enabled`）
- private コンテナと SAS トークン（権限・HTTPS・有効期限）による一時共有
- Private Endpoint による閉域化（VNet / サブネット / NIC）
- Private DNS Zone（`privatelink.*`）による名前解決の private IP への向け替え
- 「公開経路上の範囲制御」と「ネットワーク的な閉域化」という 2 つの守り方の違い
- VM を踏み台にした到達性テスト（内部からは到達、外部からは拒否の対比）

## まだ学習できていない概念（次プロジェクトの候補）

- Managed Identity / Azure AD 認証ベースの Blob アクセス（アクセスキー・SAS に依らない）
- ライフサイクル管理ポリシー（Hot/Cool/Archive の自動階層化）、イミュータブルストレージ
- Blob 以外のサービス（File / Queue / Table / Data Lake Gen2）と各 Private Endpoint
- イベント連携（Event Grid / Blob トリガー）※ func/blob_logger と接続して学べる
- Service Endpoint / ファイアウォール（IP 制限）と Private Endpoint の使い分け
- レプリケーション（GRS/ZRS 等）・ジオ冗長・フェイルオーバー
- 顧客管理キー（CMK）による暗号化
