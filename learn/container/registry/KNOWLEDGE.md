# KNOWLEDGE — container/registry で新たに出た用語・概念

ACR / `az acr build` / Managed Identity / AcrPull / RBAC など、**automate・k8s トピックで既出**の
基礎語は再掲しない。ここでは「ACR を *主役* として正面から扱う」ことで初めて要る語に絞る。

## レジストリの中身の構造

- **repository（リポジトリ）**: レジストリ内のイメージ名前空間（例 `web`）。1 レジストリに複数置ける。
  `az acr repository list` で一覧、`az acr repository show-tags --repository web` でタグ一覧。
- **tag（タグ）**: 人が読む可動ラベル（例 `v1`）。**上書き可能**＝同じ名前で別の中身を指せる。
- **manifest（マニフェスト）**: イメージの構成（レイヤの集合・config）を記述したメタデータ。
  pull の実体はこのマニフェストを digest で取りに行く。
- **digest（ダイジェスト）**: マニフェストの **SHA256 ハッシュ**（`sha256:...`）。
  内容が 1 バイトでも違えば別の digest になる＝**不変の指し先**。
  - **tag vs digest**: `web:v1` は動く参照、`web@sha256:...` は不変参照。
    再現性が必要なデプロイは digest 固定が安全。`local/docker` 案7 のローカル版をクラウドで再確認。
  - **同じタグの上書き**: 中身を変えて同じ `v1` で push すると、タグ `v1` の指す digest が変わり、
    古い digest は**タグの無い宙ぶらりん（dangling）マニフェスト**として残る（digest 指定なら今も pull 可）。

## 認証（authn）— レジストリへのログイン方法

- **admin user**: レジストリに 1 組だけ持てる**共有 username/password**。`adminUserEnabled` で切替、
  `az acr credential show` で取得。手軽だが**全員で 1 つの秘密を共有**するアンチパターン。既定は無効。
- **Entra トークン認証（`az acr login`）**: 自分の Entra ログインを ACR 用の**短命リフレッシュトークン**に
  交換して docker クライアントへ渡す方式。共有パスワード不要＝**キーレス**。admin user 無効でもこれで push/pull できる。
- **どちらで「ログインできるか」と、ログイン後に「pull/push できるか」は別**（後者は下の RBAC）。

## 認可（authz）— ACR のロール

automate/k8s では **AcrPull**（pull 専用）だけ使ってきたが、ACR には用途別のロール群がある：

- **AcrPull**: pull のみ（実行環境・消費者向け）。
- **AcrPush**: pull + push（CI / 開発者向け）。
- **AcrDelete**: イメージ/タグの削除。
- `Owner`/`Contributor` などの管理ロールはこれらを内包する。
- ロールは **ACR リソースをスコープ**に割り当てる（`az role assignment create --scope <acrId>`）。
  認証が通っても**適切なロールが無ければ pull/push は 403**＝認証と認可の分離。
- **マネージド ID はローカルから使えない**: UAMI は Azure リソースの中からしか
  トークンを取れない（IMDS 経由）。手元のラップトップから UAMI に成り代わって pull は不可。
  そのため AcrPull の因果をローカルで観測したいときは、**AcrPull だけ持つ SP（サービスプリンシパル）**
  を非特権 ID の代役にする（`docker login -u <appId> -p <secret>`）。`docker login`（認証）は
  通るが、AcrPull が無いと `docker pull`（認可）が落ちる、で authn/authz の分離も見える。

## ビルドとツール

- **ACR Tasks（`az acr build`）**: Dockerfile とコンテキストを ACR に送り、**クラウド側でビルドして
  そのまま push** する。ローカル Docker 不要。`--build-arg` でビルド引数を渡せる（本プロジェクトの
  `VERSION` 焼き込みに利用）。automate でも使ったが、ここでは「ビルド場所＝レジストリ側」という性質を主役に。
- **`az acr manifest list-metadata`**: リポジトリ内の各マニフェストの digest / tags / 作成時刻を一覧。
  tag と digest の対応・宙ぶらりんマニフェストの確認に使う。
- **`az acr check-health`**: CLI 設定・到達性・認証など ACR まわりの健全性を診断する。
- **`az acr repository show-tags` / `list`**: タグ・リポジトリの一覧。

## イメージスキャン（このプロジェクトでは設定のみ言及）

- **Microsoft Defender for Cloud（Defender for Containers）**: 有効化すると ACR への push 時に
  **脆弱性スキャン**が自動実行され、結果が「セキュリティの推奨事項」に出る。
  ACR 単体機能ではなくサブスクリプション/プラン依存のため、本プロジェクトの Bicep には含めない。
