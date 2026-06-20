# container / registry — ACR（クラウドのイメージ置き場）が主役

container トピックの **Step 1**（ロードマップは [../PLAN.md](../PLAN.md)）。
このトピックの軸は「**自作コンテナイメージを、オーケストレーションを自前で持たずに Azure の
マネージド計算へそのまま載せて動かす**」。その全ステップ（aci / webapp-container / container-apps）は
「**ここに上げたイメージを各サービスが pull する**」前提なので、最初に **Azure Container Registry (ACR)**
を土台として固める。

共通方針（[../../CLAUDE.md](../../CLAUDE.md)）どおり：
**一般概念 → 最小構成で実装 → 設定を出し入れして因果を確かめる**／**構築・実行はユーザー自身が行う**。

> 構成と各実験の図は [MERMAID.md](MERMAID.md) を参照。

## 一般概念（ベンダー非依存）

- **コンテナレジストリ**＝イメージの置き場。Docker Hub / GHCR と同じ役割で、ACR はその Azure 版。
- **repository / tag / digest**:
  - *repository*: イメージの名前空間（例 `web`）。
  - *tag*: 人が読む可動ラベル（例 `v1`）。**上書きできる＝指し先が動く**。
  - *digest*: 中身（マニフェスト）の SHA256 ハッシュ（例 `sha256:...`）。**内容が同じなら同じ・違えば必ず違う＝不変**。
- **認証(authn)と認可(authz)は別**:
  - レジストリへのログイン方法 = authn（共有パスワード or Entra トークン）。
  - そのうえで pull/push できるか = authz（RBAC ロール、AcrPull / AcrPush 等）。

## このプロジェクトで作るもの

[main.bicep](main.bicep) が作るのは 3 つだけ：

1. **ACR**（`adminUserEnabled=false`＝既定でキーレス）。
2. **消費者 User-Assigned Managed Identity**（後続サービスが pull に使う ID）。
3. その UAMI への **AcrPull** ロール割り当て（ACR スコープ）。

イメージは [app/](app/)（nginx で静的ページを配信する最小イメージ）を `az acr build` で焼く。
`__VERSION__` を build-arg `VERSION` で焼き込むので、「同じタグ・違う中身」を作れる（digest 実験用）。

リポジトリ名は既定 `web`（**レジストリ内で一意なら何でもよい**名前空間）。`.env` の `REPO` で差し替え可
（実体は [scripts/_lib.ps1](scripts/_lib.ps1) の `Get-Config` に一元化してあり、各スクリプトはそこを参照する）。

## 前提

- Azure CLI（`az`）でログイン済み・サブスクリプション選択済み。
- [Task](https://taskfile.dev)（`task`）。`go-task` / winget / scoop 等で導入。
- **ローカル Docker は不要**（クラウドビルド `az acr build` を主経路にしている）。
  `push-local` / `pull-test` と `acrpull-*` 実験だけは任意で Docker を使う。
- `acrpull-*` 実験は **SP を作成/削除**する（`az ad sp create-for-rbac` / `az ad sp delete`）。
  アプリ登録を作れる権限が要る（auth トピックの `register` と同じ前提）。

## 手順

```pwsh
# 1) RG 作成 → Bicep デプロイ → v1 をクラウドビルドまで一括
task up

# 出力（ACR 名 / ログインサーバ / 消費者 UAMI）を確認
task outputs
```

`task up` は `group-create` → `deploy` → `build`（web:v1）を順に実行する。個別にも叩ける。

## 因果を確かめる実験（ここが本体）

### 1. tag vs digest（不変性）

```pwsh
task digest-demo   # 同じタグ web:v1 を中身だけ変えて 2 回ビルド
task inspect       # タグ・マニフェスト(digest)一覧を確認
```

同じタグ `v1` のまま **digest が変わる**のが見える。
=> **tag は動く参照／digest は不変の指し先**。再現性が要るデプロイは `web@sha256:...`（digest 指定）が安全、
という後続ステップでの作法につながる。

### 2. admin user（共有パスワード）の出し入れ

```pwsh
task admin-on    # 有効化 → az acr credential show で共有 username/password が見える
task admin-off   # 無効化（既定・推奨）→ credential が取れない＝Entra トークン認証のみ
```

admin user は「**全員で 1 つのパスワードを共有する**」アンチパターン。
無効のまま **Entra トークン認証（`az acr login`）＋ RBAC** で運用するのが第一選択だと体感する。

### 3. AcrPull（認可）で pull の可否が変わる（要 Docker）

認証（誰か）はそのままでも、**認可（AcrPull があるか）で pull できる/できないが変わる**。
消費者 **UAMI（マネージド ID）は Azure リソースの中からしか使えない**（IMDS 経由でトークンを取る）ため、
手元のラップトップから UAMI に成り代わって pull することは**原理的にできない**。そこでこの実験では
「**AcrPull だけ持つサービスプリンシパル(SP)**」を非特権 ID の代役にする。

**段階実行**（各ステップは独立。特に `acrpull-pull` は **ロールを一切触らない**ので、反映待ちでも何度でも再実行できる）:

```pwsh
task acrpull-setup    # AcrPull だけ持つ SP を作成（資格情報をローカル保存）
task acrpull-pull     # pull → 成功（AcrPull あり）
task acrpull-revoke   # SP から AcrPull を外す
task acrpull-pull     # ★少し待って何度でも → やがて 403 に変わる（ロールは触らないので再実行で観測できる）
task acrpull-grant    # AcrPull を付け直す
task acrpull-pull     # 待って再実行 → また成功
task acrpull-cleanup  # テスト用 SP と保存資格情報を削除
```

**`docker login`（認証）は通るのに pull（認可）だけ落ちる**ので、認証と認可の分離も同時に体感できる。
RBAC の反映には数十秒〜数分かかることがあるが、`acrpull-pull` はロールを変えないため、**待って再実行すれば**
成功→403（や 403→成功）の切り替わりを観測できる（旧版の「一気に流す」方式の弱点を解消）。

> 注: `acrpull-setup` は SP の秘密をローカルの `.acrpull-demo.json`（gitignore 済み）に保存する。
> 使い終わったら必ず `task acrpull-cleanup` で SP と state を消すこと。

> **UAMI 本人での 403 は Step 2 へ**: この ACR に作った消費者 UAMI を主語にした「AcrPull を外すと pull 失敗」は、
> UAMI を assign できる計算リソースが要るので **Step 2（aci）** で行う。Step 1 では UAMI に AcrPull を付けた
> 土台（Bicep の `deploy`）を用意するところまで。

### 4.（任意・要 Docker）キーレス pull / ローカルビルド経路

```pwsh
task push-local    # az acr login(トークン認証) → docker build → push
task pull-test     # az acr login → docker pull（admin user 無しで pull できる＝キーレス）
```

## 後片付け（コスト注意）

ACR Basic は容量課金がごく小さいが、使い終わったら破棄する。

```pwsh
task destroy   # リソースグループごと削除
```

> **後続ステップへ**: この ACR / ログインサーバ / 消費者 UAMI を、Step 2 以降の各サービスが
> そのまま参照する。`task outputs` の値（特に `acrLoginServer` と `uamiResourceId`）が引き継ぎ点。

## イメージスキャン（メモ）

イメージの脆弱性スキャンは ACR 単体ではなく **Microsoft Defender for Cloud（Defender for Containers）**
を有効化すると push 時に自動で走る（サブスクリプション/プラン依存のため本プロジェクトの Bicep には含めない）。
有効時は Defender の「セキュリティの推奨事項」または `az acr` のレジストリ画面から結果を確認する。

## タスク一覧

| task | 説明 |
|---|---|
| `up` | group-create → deploy → build(v1) を一括 |
| `deploy` | ACR + 消費者 UAMI + AcrPull を Bicep でデプロイ |
| `build [TAG=v1]` | `az acr build` でクラウドビルド & push |
| `outputs` | デプロイ出力を表示 |
| `inspect` | リポジトリ/タグ/マニフェスト(digest)/health |
| `digest-demo` | 同タグ上書きで digest が変わるのを観察 |
| `admin-on` / `admin-off` | admin user の出し入れ |
| `acrpull-setup` / `acrpull-pull` / `acrpull-revoke` / `acrpull-grant` / `acrpull-cleanup` | （要 Docker）SP を代役に pull の成功⇄403 を段階実行で観測 |
| `push-local` / `pull-test` | （任意/要 Docker）ローカルビルド・キーレス pull |
| `destroy` | RG ごと削除 |
