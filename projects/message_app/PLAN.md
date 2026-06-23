# PLAN — メッセージアプリ 設計 V3.0

V1 設計（4 サービス構成・キャッシュ戦略・Cosmos パーティション）は `versions/v1/PLAN.md`、
V2 設計（認証・JWT・友達リスト）は `versions/v2/PLAN.md` を参照。
本書は **V3 で行う「知り合い／友達の二段階関係」「友達ゲートのメッセージ送信」「キャッシュ無効化の正常化」** の設計だけを固定する。

## 全体構成への影響（責務分担の差分）

V1/V2 の役割分担はそのまま。新サービスの追加はない。各サービスに足す／変える責務：

| コンポーネント | V3 で追加・変更する責務 |
| --- | --- |
| Frontend | 「知り合い」「自分を知り合い登録している人(inbound)」「友達」の 3 ビュー。送信先は友達のみ選べる UI |
| BFF | 変更なし（JWT 検証 → `X-User` 注入はそのまま）。ルートのパスのみ `friends` → `acquaintances` 系に追従 |
| Backend(読み取り / FastAPI) | 知り合い一覧 / inbound 一覧 / **友達一覧（積集合の導出）** を read-through キャッシュで返す |
| Backend(書き込み / Functions) | 知り合いの追加/削除（**関連する全キャッシュを無効化**）、メッセージ送信に**友達ゲート**と**双方向キャッシュ無効化**を追加 |

**なぜこの割り当てか**：
- 「友達一覧」は読み取り＋計算（積集合の導出）なので FastAPI（V2 の login/friends 一覧の流れを踏襲）。
- 関係を変える書き込み（知り合い追加/削除）と送信は Functions（CQRS 的分離の継続）。
- 友達ゲート（送信可否の判定）は**書き込みの直前条件**なので、送信を担う Functions 側に置く。

## 関係モデルの再設計（V3 の中心）

### 用語と方向
- **知り合い（acquaintance）**：一方向 `A→B`。V2 までの「友達」を改名したもの。
- **inbound**：逆向き `B→A`。「自分を知り合い登録している人」。
- **友達（friend）**：`A→B` かつ `B→A` が両方成立した**相互マッチ**。別保存せず導出する。

### データモデル：コンテナ `acquaintances`（パーティションキー `/owner`、**dual-write**）
V2 の `friends` コンテナを**改名**し、構造も変える（命名の移行表は後述）。
inbound と友達の導出が**明らかに頻出**（一覧表示・友達ゲートが送信ごとに走る）なので、
**最初から全ビューを単一パーティション化**する。そのために「A が B を知り合い登録」した時、
**2 つのミラー文書**を書く（fan-out on write）：

```jsonc
// 「alice が bob を知り合い登録」= 以下の 2 文書（dual-write）
{ "id": "out__alice__bob", "owner": "alice", "direction": "out", "peer": "bob",   "createdAt": "..." } // alice 視点：発信
{ "id": "in__bob__alice",  "owner": "bob",   "direction": "in",  "peer": "alice", "createdAt": "..." } // bob 視点：受信(inbound)
```
- `owner` は**「この行が誰のビューに属するか」**（= パーティションキー）。`direction` は発信(`out`)／受信(`in`)、`peer` は相手。
- id は `{direction}__{owner}__{peer}` の決め打ち → 同じ登録を何度実行しても重複しない（**冪等**）。

### 3 つのビューの導出（すべて単一パーティション）
全ビューが `owner=me` の**単一パーティション・クエリ**で完結する（dual-write の対価）。
| ビュー | クエリ | パーティション |
| --- | --- | --- |
| 自分の知り合い | `WHERE c.owner=@me AND c.direction='out'` → `peer` を集める | **単一**（owner=me） |
| 自分を知り合い登録している人(inbound) | `WHERE c.owner=@me AND c.direction='in'` → `peer` を集める | **単一**（owner=me） |
| 友達（相互） | `WHERE c.owner=@me` を取り、**out の peer と in の peer の積集合**をアプリ側で取る | **単一**（同一パーティション内で完結） |

> **dual-write の対価（重要な学習点）**：2 文書は **owner=A と owner=B の別パーティション**にまたがる。
> Cosmos の **TransactionalBatch は単一パーティション限定**なので、この 2 書き込みは**1 トランザクションにできない**。
> → 決定的 id の**冪等 upsert / delete**で best-effort にし、片側だけ書けて落ちても再実行で収束させる。
> 厳密な整合（孤立エッジの修復）が要るなら、定期リコンサイル or Change Feed で対向を補完する（将来テーマ）。
> 「**読み取りを単一パーティション化する代わりに、書き込み増幅と多パーティション整合の責任を負う**」という典型的トレードオフを体験する。

### 友達ゲート（メッセージ送信の認可）
dual-write のおかげで、相互マッチの確認は**送信者 1 人の partition だけ**で済む：
- `out__A__B`（PK=A）が存在するか（A→B：A が B を登録）
- `in__A__B`（PK=A）が存在するか（B→A のミラー：B が A を登録）
- **両方とも partition=A のポイントリード**。両方あれば友達 → 送信許可。片方でも欠ければ **403**。

> V2 の素朴設計なら `A__B`(PK=A) と `B__A`(PK=B) で**2 パーティション**に触れる必要があった。
> dual-write で受信エッジを A の partition にもミラーしているため、**1 パーティション**で判定できる。

> **認証と認可の分離**：誰か（authn）は V2 の JWT 検証で済んでいる。V3 が足すのは
> **その人がこの宛先に送ってよいか（authz）**＝関係チェック。両者は別レイヤだと理解する。

## キャッシュ設計（V3 の二本目の柱：陳腐化の正常化）

### 一般原則
> **リソースを変える書き込みは、そのリソースが寄与する全キャッシュを無効化する。**
> 「どのキャッシュが古くなるか」は、**操作の影響範囲**から機械的に導く（自分だけか／他人に及ぶか）。

V2 までは学習目的で「送信時に受信者のキャッシュをあえて無効化しない」陳腐化を残していた。
V3 はこれを撤廃し、旧機能（会話）・新機能（関係）の両方でこの原則を貫く。

### キャッシュ一覧と無効化規則
| キー | 内容 | TTL | 無効化トリガ（リソース変更 → 無効化対象） |
| --- | --- | --- | --- |
| `conv:{viewer}:{pair}` | viewer から見た会話 | 60s | `pair` にメッセージ送信 → **送信者・受信者 双方**の `conv` を無効化 |
| `acq:{owner}` | owner の知り合い一覧 | 60s | owner が知り合いを追加/削除 → `acq:{owner}` |
| `acqby:{target}` | target を知り合い登録している人(inbound) | 60s | 誰かが target を知り合いに追加/削除 → `acqby:{target}` |
| `friends:{user}` | user の友達（相互）一覧 | 60s | user に関わる相互マッチが成立/解消 → `friends:{user}` |

### 操作ごとの無効化（影響範囲から導く）
- **メッセージ送信 `A→B`**：会話は両者で共有 → `conv:A:{pair}` と `conv:B:{pair}` を**両方**無効化。
  - V2 との違い：V2 は `conv:A` だけ更新し `conv:B` を放置（＝陳腐化）。V3 は B も無効化する。
- **知り合い追加 `A→B`**：
  1. `acq:A` 無効化（A の知り合いが増えた）。
  2. `acqby:B` 無効化（B の inbound が増えた）。
  3. すでに `B→A` があれば**相互マッチ成立** → `friends:A` と `friends:B` を無効化。
- **知り合い削除 `A→B`**：
  1. `acq:A` 無効化。
  2. `acqby:B` 無効化。
  3. 削除前に友達だった（`B→A` がある）なら**マッチ解消** → `friends:A` と `friends:B` を無効化。

> **V2 からの世界観の変化**：V2 PLAN は「友達リストは一方向・自己完結なので他人のキャッシュに影響しない＝陳腐化の構図が無い」と書いた。
> V3 で**相互マッチ**を入れた瞬間、A の操作は B の inbound／友達ビューに影響する。
> → 「自己完結だから無効化不要」は**もう成り立たない**。だから A の操作で **B 側のキャッシュも**無効化する。
> これが V2 で予告していた「将来、友達同士のみ送信可にすると陳腐化が再登場する」の回収である。

## API（V3・BFF が公開）

V1/V2 の `/api/users` `/api/conversation` `/api/messages` `/api/login` 等は維持。
V2 の `friends` 系ルートを **`acquaintances` 系へ改名**し、inbound と友達一覧を追加する。

| メソッド | パス | 振り分け先 | 認証 | 説明 | V2 からの変化 |
| --- | --- | --- | --- | --- | --- |
| GET | `/api/acquaintances` | FastAPI | 要 | 自分の知り合い一覧 | 旧 `GET /api/friends` を改名 |
| POST | `/api/acquaintances` | Functions | 要 | `{username}` を知り合い追加（冪等） | 旧 `POST /api/friends` を改名 |
| DELETE | `/api/acquaintances/{username}` | Functions | 要 | 知り合い削除 | 旧 `DELETE /api/friends/{username}` を改名 |
| GET | `/api/acquaintances/inbound` | FastAPI | 要 | 自分を知り合い登録している人 | **新規** |
| GET | `/api/friends` | FastAPI | 要 | 友達（相互マッチ）一覧 | **意味変更**：導出（積集合）になった |
| POST | `/api/messages` | Functions | 要 | メッセージ送信 | **友達ゲート追加**（非友達は 403）＋双方向キャッシュ無効化 |

## 命名の移行表（ドキュメント＋コードで一貫させる）

| 種別 | V2 | V3 |
| --- | --- | --- |
| 概念（一方向） | 友達 | **知り合い（acquaintance）** |
| 概念（双方向） | —（無し） | **友達（friend＝相互マッチ）** |
| Cosmos コンテナ | `friends`（PK `/owner`、1 登録=1 文書） | `acquaintances`（PK `/owner`、**1 登録=2 ミラー文書**） |
| ドキュメントフィールド | `friend` | `direction`(`out`/`in`) ＋ `peer`（id=`{direction}__{owner}__{peer}`） |
| store の参照 | `friends_container` | `acquaintances_container` |
| Functions（追加） | `add_friend` / route `friends` | `add_acquaintance` / route `acquaintances` |
| Functions（削除） | `remove_friend` / route `friends/{username}` | `remove_acquaintance` / route `acquaintances/{username}` |
| FastAPI（一覧） | `list_friends` / `GET /friends` | `list_acquaintances` / `GET /acquaintances` ＋ `list_inbound`(`/acquaintances/inbound`) ＋ `list_friends`(`/friends`＝相互) |
| キャッシュキー | `friends:{owner}` | `acq:{owner}` / `acqby:{target}` / `friends:{user}`（相互） |

> **コードへの反映**は本ドキュメントの確定後に行う（このコミットは設計のみ）。
> 実装時は CLAUDE.md の「ファイル配置・規約」に従い、`api/` と `functions/` の `store.py` 重複を両方そろえて更新する。

## `users` / その他コンテナ
- `users`（V2 で追加した `email`/`passwordHash`/`emailVerified` 等）は**変更なし**。
- `messages`（PK `/pairKey`）は**変更なし**。送信時の**キャッシュ無効化のみ**変える（受信者側も無効化）。

## ローカル / Azure の対応（V3 差分）
- 新しい依存・環境変数の追加は**なし**（V2 のまま）。
- Cosmos コンテナ名が `friends` → `acquaintances` に変わるため、`store.init_cosmos()` の作成対象を差し替える。
  既存ローカル Emulator は作り直すか、`acquaintances` を新規作成する（旧 `friends` のデータ移行は学習スコープ外・KNOWLEDGE.md 参照）。

## ディレクトリ構成（V3 変更分）
```
projects/message_app/
├── （V1/V2 の構成はそのまま：api / functions / bff / infra / scripts / Taskfile.yml）
├── functions/   # add/remove を acquaintance 系へ改名。送信に友達ゲート＋双方向無効化を追加
├── api/         # acquaintances 一覧 / inbound 一覧 / friends(相互) 一覧 を実装
├── bff/         # 知り合い/inbound/友達 の 3 ビュー UI。ルートのパス追従のみ
└── infra/       # 変更なし（新リソースなし）
```
