"""書き込み処理（Azure Functions / Python v2 プログラミングモデル）。

状態を変える操作だけを担う Serverless エンドポイント（CQRS 的分離の書き込み側）。
- POST   /api/signup             body: { email, username, password }
- GET    /api/verify?token=...   メール検証（リンクのクリック先）
- POST   /api/messages           body: { to, text }            header: X-User
- POST   /api/friends            body: { username }            header: X-User
- DELETE /api/friends/{username}                               header: X-User

メッセージ送信は「送信者のキャッシュだけ更新」（受信者は陳腐化＝学習ポイント）。
友達変更は「自分の操作=自分のキャッシュ無効化」（一方向・自己完結なので陳腐化なし）。
X-User は BFF が JWT 検証後に注入した「信頼済みの本人」（signup/verify は検証前の例外）。
"""
import json
import os
import secrets
import uuid
from datetime import datetime, timezone, timedelta

import bcrypt
import azure.functions as func
from azure.cosmos.exceptions import CosmosResourceNotFoundError

import store
import email_helper

app = func.FunctionApp()

# メール内リンクの組み立てに使う公開ベース URL（BFF のオリジン）。
APP_BASE_URL = (os.getenv("APP_BASE_URL") or "http://localhost:3000").rstrip("/")
# 検証トークンの有効期間（24 時間）。
VERIFY_TOKEN_TTL = timedelta(hours=24)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@app.route(route="messages", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
def send_message(req: func.HttpRequest) -> func.HttpResponse:
    sender = (req.headers.get("X-User") or "").strip().lower()
    if not sender:
        return func.HttpResponse("X-User header is required", status_code=400)

    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse("invalid JSON body", status_code=400)

    to = (body.get("to") or "").strip().lower()
    text = (body.get("text") or "").strip()
    if not to or not text:
        return func.HttpResponse("'to' and 'text' are required", status_code=400)
    if to == sender:
        return func.HttpResponse("cannot message yourself", status_code=400)

    pk = store.pair_key(sender, to)
    message = {
        "id": str(uuid.uuid4()),
        "pairKey": pk,
        "from": sender,
        "to": to,
        "text": text,
        "createdAt": _now_iso(),
    }

    # 1) 正本(Cosmos)へ append
    store.messages_container.create_item(message)

    # 2) 送信者のキャッシュだけ作り直す（Cosmos から会話全体を取り直してセット）。
    #    受信者の conv:{to}:{pk} はあえて触らない → TTL 切れまで新着が見えない。
    #    from / to は Cosmos SQL の予約語なので SELECT * してから整形する。
    items = list(
        store.messages_container.query_items(
            query="SELECT * FROM c WHERE c.pairKey=@pk ORDER BY c.createdAt ASC",
            parameters=[{"name": "@pk", "value": pk}],
            partition_key=pk,
        )
    )
    messages = [store.shape_message(m) for m in items]
    store.cache.set(
        f"conv:{sender}:{pk}", json.dumps(messages), ex=store.CACHE_TTL_SECONDS
    )

    return func.HttpResponse(
        json.dumps(message), status_code=201, mimetype="application/json"
    )


# --- サインアップ / メール検証 ----------------------------------------------
@app.route(route="signup", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
def signup(req: func.HttpRequest) -> func.HttpResponse:
    """ユーザー作成 + パスワードハッシュ + 検証トークン発行 + 検証メール送信。

    まだトークンが無い入口なので X-User は取らない（BFF も検証せず素通し）。
    """
    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse("invalid JSON body", status_code=400)

    email = (body.get("email") or "").strip().lower()
    username = (body.get("username") or "").strip().lower()
    password = body.get("password") or ""
    if not email or not username or not password:
        return func.HttpResponse(
            "email, username and password are required", status_code=400
        )

    # username はパーティションキー(id)。既存なら 409（上書き＝乗っ取りを防ぐ）。
    try:
        store.users_container.read_item(item=username, partition_key=username)
        return func.HttpResponse("username already taken", status_code=409)
    except CosmosResourceNotFoundError:
        pass

    # パスワードはハッシュのみ保存（平文・可逆暗号は使わない）。
    password_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
    # 検証トークン（推測困難なランダム）。検証後はクリアする。
    token = secrets.token_urlsafe(32)
    expires = datetime.now(timezone.utc) + VERIFY_TOKEN_TTL

    store.users_container.upsert_item(
        {
            "id": username,
            "username": username,
            "email": email,
            "passwordHash": password_hash,
            "emailVerified": False,
            "verifyToken": token,
            "verifyTokenExpires": expires.isoformat(),
            "createdAt": _now_iso(),
        }
    )
    # 新規ユーザーが増えたので users 一覧キャッシュを破棄（読み取り側が次回再構築）。
    store.cache.delete("users:all")

    # 検証リンクは BFF 経由のパス（GET /api/verify?token=...）。
    verify_link = f"{APP_BASE_URL}/api/verify?token={token}"
    email_helper.send_verification_email(email, verify_link)

    return func.HttpResponse(
        json.dumps({"username": username, "emailVerified": False}),
        status_code=201,
        mimetype="application/json",
    )


@app.route(route="verify", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def verify(req: func.HttpRequest) -> func.HttpResponse:
    """メールのリンク先。token を引いて有効なら emailVerified=true にする。

    ブラウザで直接開かれるので、結果は小さな HTML で返す。
    token はパーティションキーでないのでクロスパーティション・クエリ。
    """
    token = (req.params.get("token") or "").strip()
    if not token:
        return _verify_html("リンクが正しくありません（token がありません）。", ok=False)

    items = list(
        store.users_container.query_items(
            query="SELECT * FROM c WHERE c.verifyToken=@token",
            parameters=[{"name": "@token", "value": token}],
        )
    )
    if not items:
        return _verify_html("リンクが無効か、すでに検証済みです。", ok=False)

    user = items[0]
    expires_raw = user.get("verifyTokenExpires")
    if expires_raw:
        expires = datetime.fromisoformat(expires_raw)
        if datetime.now(timezone.utc) > expires:
            return _verify_html("リンクの有効期限が切れています。再登録してください。", ok=False)

    # 検証済みに更新し、トークンを失効（再利用させない）。
    user["emailVerified"] = True
    user["verifyToken"] = None
    user["verifyTokenExpires"] = None
    store.users_container.upsert_item(user)

    return _verify_html(
        f"{user['username']} のメール検証が完了しました。ログインできます。", ok=True
    )


def _verify_html(message: str, ok: bool) -> func.HttpResponse:
    color = "#16a34a" if ok else "#dc2626"
    html = (
        "<!doctype html><html lang='ja'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        "<title>メール検証</title></head>"
        "<body style='font-family:system-ui,sans-serif;background:#0f172a;color:#e2e8f0;"
        "display:flex;align-items:center;justify-content:center;height:100vh;margin:0'>"
        "<div style='background:#1e293b;padding:2rem 2.5rem;border-radius:12px;text-align:center'>"
        f"<p style='font-size:1.1rem;color:{color}'>{message}</p>"
        f"<a href='{APP_BASE_URL}/' style='color:#38bdf8'>アプリへ戻る</a>"
        "</div></body></html>"
    )
    return func.HttpResponse(html, status_code=200, mimetype="text/html")


# --- 友達 追加 / 削除 -------------------------------------------------------
@app.route(route="friends", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
def add_friend(req: func.HttpRequest) -> func.HttpResponse:
    """owner（X-User）の友達リストに friend を追加（冪等）。

    一方向：owner 側にだけ作る。自分のキャッシュ friends:{owner} を無効化する
    （他人のキャッシュには影響しない＝陳腐化の構図が無い。PLAN.md 参照）。
    """
    owner = (req.headers.get("X-User") or "").strip().lower()
    if not owner:
        return func.HttpResponse("X-User header is required", status_code=400)

    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse("invalid JSON body", status_code=400)

    friend = (body.get("username") or "").strip().lower()
    if not friend:
        return func.HttpResponse("'username' is required", status_code=400)
    if friend == owner:
        return func.HttpResponse("cannot add yourself", status_code=400)

    # id=owner__friend を決め打ち upsert → 同じ追加を何度しても重複しない（冪等）。
    doc = {
        "id": f"{owner}__{friend}",
        "owner": owner,
        "friend": friend,
        "createdAt": _now_iso(),
    }
    store.friends_container.upsert_item(doc)
    store.cache.delete(f"friends:{owner}")  # 自分の操作 → 自分のキャッシュを無効化

    return func.HttpResponse(json.dumps(doc), status_code=201, mimetype="application/json")


@app.route(
    route="friends/{username}", methods=["DELETE"], auth_level=func.AuthLevel.ANONYMOUS
)
def remove_friend(req: func.HttpRequest) -> func.HttpResponse:
    """owner（X-User）の友達リストから friend を削除（冪等）。"""
    owner = (req.headers.get("X-User") or "").strip().lower()
    if not owner:
        return func.HttpResponse("X-User header is required", status_code=400)

    friend = (req.route_params.get("username") or "").strip().lower()
    if not friend:
        return func.HttpResponse("username is required", status_code=400)

    try:
        store.friends_container.delete_item(item=f"{owner}__{friend}", partition_key=owner)
    except CosmosResourceNotFoundError:
        # 既に無い場合も成功扱い（冪等）。
        pass
    store.cache.delete(f"friends:{owner}")

    return func.HttpResponse(status_code=204)
