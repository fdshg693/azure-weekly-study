# PLAN — メッセージアプリ 設計 V2.0

V1 設計（4 サービス構成・キャッシュ戦略・Cosmos パーティション）は `versions/v1/PLAN.md` を参照。
本書は **V2 で追加する「認証（パスワード + メール検証）」「友達リスト」** の設計だけを固定する。

## 全体構成への影響（責務分担の差分）

V1 の役割分担はそのまま。V2 で各サービスに足す責務：

| コンポーネント | V2 で追加する責務 |
| --- | --- |
| Frontend | サインアップ / ログイン / 検証待ち画面、トークン保持（`localStorage`）、`Authorization: Bearer` 付与、友達リスト UI |
| BFF | **JWT 検証**。検証成功で `username` を取り出し、下流へ **信頼済み `X-User`** を注入。失敗は 401。auth/friends のルーティング |
| Backend(読み取り / FastAPI) | **login**（パスワード検証 → JWT 発行）、**友達リスト取得**（read-through キャッシュ） |
| Backend(書き込み / Functions) | **サインアップ**（ユーザー作成 + パスワードハッシュ + 検証トークン発行 + メール送信）、**メール検証**、**友達 追加 / 削除** |
| ACS (Email) | 検証メールの実送信。Functions から呼ぶ（`EMAIL_MODE=local` ではモック） |

**なぜこの割り当てか**：
- パスワード検証＆トークン発行は「読み取り＋計算」なので FastAPI（V1 で login が FastAPI にあった流れを踏襲）。
- サインアップ／検証／友達変更は **状態を変える＝書き込み**なので Functions（CQRS 的分離の継続）。
- **メール送信はイベント駆動・従量で Functions に向く**。将来はキュー(Storage Queue)トリガで送信を分離できる（V2 ではサインアップ関数内で同期送信、分離は将来）。

## 認証設計

### 信頼境界（V1 → V2 の変化）
- V1：client が `X-User` を自己申告 → 詐称可能。
- V2：client は **JWT** を送る → **BFF が署名検証** → 本人 `username` を取り出し、下流へ `X-User` として転送。
  下流（FastAPI / Functions）は **BFF（内部ネットワーク）からの `X-User` を信頼**する。
  - login と verify は「まだトークンが無い／不要」な入口なので、この検証の例外（BFF はそのまま下流へ流す）。

### パスワード
- 保存は **ハッシュのみ**（`passwordHash`）。アルゴリズムは bcrypt（または argon2）。平文・可逆暗号は使わない。
- 検証は `verify(password, passwordHash)`。タイミング安全な比較を用いる。

### メール検証フロー
1. サインアップ：`users` に **未検証**で作成、`passwordHash` を保存、**検証トークン**（ランダム）と失効時刻を保存。
2. メール送信：`APP_BASE_URL` を使い `…/api/verify?token=<token>` のリンクを組み立てて送る。
   - `EMAIL_MODE=local`：送らず、リンクをコンソール＋ `.verify-links/<email>.txt` に出力（gitignore）。
   - `EMAIL_MODE=acs`：ACS Email で実送信。
3. 検証：`GET /api/verify?token=` でトークンを引き、有効なら `emailVerified=true`、トークンを失効。
4. ログイン：`emailVerified=true` のときだけ JWT を発行。未検証は 403（理由を返す）。

### セッショントークン（JWT）
- ステートレス。`JWT_SECRET`（HMAC）で署名、`JWT_TTL_SECONDS`（既定 3600）で失効。
- ペイロード：`{ sub: <username>, email, iat, exp }`。
- 検証は **BFF** が毎リクエストで実施（署名・exp）。失効/改ざんは 401。
- **代替案**：Redis にセッションを持つ方式（失効を即時にできる）。V2 は学習を絞るためステートレス JWT を採用し、
  サーバー側失効（ログアウト即無効化）は将来テーマとする。

## 友達リスト設計

### データモデル：コンテナ `friends`（パーティションキー `/owner`）
```jsonc
{
  "id": "alice__bob",   // owner + friend で一意（重複追加を冪等にする）
  "owner": "alice",     // リストの持ち主（= パーティションキー）
  "friend": "bob",
  "createdAt": "2026-06-23T12:00:00Z"
}
```
- **一方向**：`alice` が `bob` を追加しても `bob` 側には作らない（相互フレンドは V2 スコープ外）。
- 友達一覧の取得は `owner` 単一パーティション・クエリ（V1 の `pairKey` と同じ発想）。

### キャッシュ（自己完結なので陳腐化しない）
| キー | 内容 | TTL | 無効化 |
| --- | --- | --- | --- |
| `friends:{owner}` | owner の友達一覧 | 60s | owner 自身の追加/削除時に `friends:{owner}` を削除 |

> **V1 との違い（誤解しやすい点）**：これは「正しい無効化 vs あえてしない無効化」の対比では**ない**。
> V1 でも送信者は**自分の** `conv` キャッシュを更新していた（自分の操作 → 自分のキャッシュ、は同じ）。
> V1 で意図的にやらなかったのは「自分の操作が**他人**のキャッシュ（受信者の会話）に影響するのに、それを無効化しない」こと。
> 友達リストは **一方向・自己完結**で、A の操作は B のリストに影響しない。よって**他人のキャッシュが陳腐化する構図がそもそも無い**。
> （将来「友達同士のみ送信可」にすると、A の追加が B の“送れる相手”ビューに影響しうる → そこで初めて陳腐化の話が再登場する。V2 ではスコープ外。）

## `users` コンテナの拡張（V1 からの差分）
V1 の `users`（パーティションキー `/id`、`id = username`）に列を追加：
```jsonc
{
  "id": "alice", "username": "alice", "createdAt": "...",
  "email": "alice@example.com",      // 追加：ログインの引き
  "passwordHash": "<bcrypt>",        // 追加
  "emailVerified": false,            // 追加：検証ゲート
  "verifyToken": "<random>",         // 追加：検証中のみ。検証後はクリア
  "verifyTokenExpires": "..."        // 追加
}
```
- **ログインは email 引き**：パーティションキーは `/id`(username) なので email 検索は **クロスパーティション・クエリ**。
  小規模学習では許容。将来は email→username のルックアップ（別コンテナ or `id=email`）を検討（KNOWLEDGE.md に記載）。
- **検証は token 引き**：同様にクロスパーティション・クエリ。

## API（V2・BFF が公開）

V1 の `/api/users` `/api/conversation` `/api/messages` は維持。ただし **要トークン**（BFF が `X-User` を注入）。

| メソッド | パス | 振り分け先 | 認証 | 説明 |
| --- | --- | --- | --- | --- |
| POST | `/api/signup` | Functions | 不要 | `{email, username, password}` 登録＋検証メール送信 |
| GET | `/api/verify?token=` | Functions | 不要 | メール検証。成功で `emailVerified=true` |
| POST | `/api/login` | FastAPI | 不要 | `{email, password}` 検証 → JWT 返却（未検証は 403） |
| GET | `/api/friends` | FastAPI | 要 | 自分（`X-User`）の友達一覧 |
| POST | `/api/friends` | Functions | 要 | `{username}` を友達追加（冪等） |
| DELETE | `/api/friends/{username}` | Functions | 要 | 友達削除 |

## ローカル / Azure の対応（V2 差分）
| 依存 | ローカル | Azure |
| --- | --- | --- |
| メール送信 | `EMAIL_MODE=local`：リンクをコンソール/ファイル出力 | `EMAIL_MODE=acs`：ACS Email で実送信 |
| JWT 秘密鍵 | `.env` の `JWT_SECRET` | App Settings（将来は Key Vault） |
| ACS 接続情報 | （未使用） | `ACS_CONNECTION_STRING` / `ACS_SENDER_ADDRESS` |

## ディレクトリ構成（V2 追加分）
```
projects/message_app/
├── （V1 の構成はそのまま：api / functions / bff / infra / scripts / Taskfile.yml）
├── infra/modules/communication.bicep   # 追加：ACS + Email ドメイン
├── functions/                           # signup / verify / friends(add,del) を追加。email 送信ヘルパ
├── api/                                 # login(JWT発行) / friends(一覧) を追加
├── bff/                                 # JWT 検証ミドルウェア、auth/friends ルート、認証 UI
└── .verify-links/                       # ローカル検証リンク出力（gitignore）
```
