"""読み取り API（FastAPI / App Service 想定）。

責務は「読み取り＋計算」：login(パスワード検証 → JWT 発行) / users 一覧 /
conversation 取得 / friends 一覧。すべて Redis を read-through キャッシュとして
経由する（miss 時だけ Cosmos）。状態を変える書き込み（signup / verify / メッセージ送信 /
友達 追加・削除）は Functions 側が担当する（CQRS 的分離。PLAN.md 参照）。

V2 の信頼境界：このサービスは BFF からの `X-User` を「検証済みの本人」として信頼する。
login だけはトークン発行前の入口なので X-User を取らない（email/password で本人確認する）。
"""
import json
from datetime import datetime, timezone, timedelta

import bcrypt
import jwt
from fastapi import FastAPI, Header, HTTPException, Query
from pydantic import BaseModel

import config
import store

app = FastAPI(title="message_app read API")


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class LoginBody(BaseModel):
    email: str
    password: str


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/login")
def login(body: LoginBody):
    """email + password を検証し、検証済みなら JWT を発行する。

    - email はパーティションキー(/id=username)ではないのでクロスパーティション・クエリ。
      小規模学習では許容（KNOWLEDGE.md：頻出キーは将来ルックアップ設計で単一化）。
    - パスワードは保存済みハッシュ(bcrypt)と照合。タイミング安全な比較は bcrypt が担う。
    - 未検証(emailVerified=false)はログイン不可（検証ゲート）→ 403。
    """
    email = body.email.strip().lower()
    if not email or not body.password:
        raise HTTPException(status_code=400, detail="email and password are required")

    # email でユーザーを引く（クロスパーティション）。曖昧化のため詳細は返さない。
    items = list(
        store.users_container.query_items(
            query="SELECT * FROM c WHERE c.email=@email",
            parameters=[{"name": "@email", "value": email}],
        )
    )
    invalid = HTTPException(status_code=401, detail="invalid email or password")
    if not items:
        raise invalid
    user = items[0]

    password_hash = user.get("passwordHash") or ""
    if not bcrypt.checkpw(body.password.encode("utf-8"), password_hash.encode("utf-8")):
        raise invalid

    if not user.get("emailVerified"):
        # 未検証は理由を返す（検証ゲートの体験）。
        raise HTTPException(status_code=403, detail="email is not verified")

    # ステートレス JWT を発行。BFF が同じ JWT_SECRET / HS256 で検証する。
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user["username"],
        "email": user["email"],
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=config.JWT_TTL_SECONDS)).timestamp()),
    }
    token = jwt.encode(payload, config.JWT_SECRET, algorithm="HS256")
    return {"token": token, "username": user["username"]}


@app.get("/users")
def list_users():
    """全ユーザー一覧。`users:all` を read-through でキャッシュ。"""
    cached = store.cache.get("users:all")
    if cached is not None:
        return {"users": json.loads(cached), "cached": True}

    users = [
        item["username"]
        for item in store.users_container.read_all_items()
    ]
    users.sort()
    store.cache.set("users:all", json.dumps(users), ex=config.CACHE_TTL_SECONDS)
    return {"users": users, "cached": False}


@app.get("/conversation")
def conversation(
    with_user: str = Query(..., alias="with"),
    x_user: str = Header(..., alias="X-User"),
):
    """X-User(=viewer) と with_user の会話一覧。

    閲覧者ごとのキャッシュキー `conv:{viewer}:{pairKey}` を使う。これにより
    「送信者は即更新 / 受信者は TTL 切れまで陳腐化」を表現できる（PLAN.md 参照）。
    """
    viewer = x_user.strip().lower()
    other = with_user.strip().lower()
    if not viewer or not other:
        raise HTTPException(status_code=400, detail="viewer and with are required")

    pk = store.pair_key(viewer, other)
    cache_key = f"conv:{viewer}:{pk}"

    cached = store.cache.get(cache_key)
    if cached is not None:
        return {"messages": json.loads(cached), "cached": True}

    # miss: Cosmos から会話を時系列で取得（単一パーティション）。
    # from / to は Cosmos SQL の予約語なので射影せず、SELECT * してから整形する。
    items = list(
        store.messages_container.query_items(
            query="SELECT * FROM c WHERE c.pairKey=@pk ORDER BY c.createdAt ASC",
            parameters=[{"name": "@pk", "value": pk}],
            partition_key=pk,
        )
    )
    messages = [store.shape_message(m) for m in items]
    store.cache.set(cache_key, json.dumps(messages), ex=config.CACHE_TTL_SECONDS)
    return {"messages": messages, "cached": False}


@app.get("/friends")
def list_friends(x_user: str = Header(..., alias="X-User")):
    """自分（X-User=owner）の友達一覧。`friends:{owner}` を read-through キャッシュ。

    一方向・自己完結なので「自分の操作=自分のキャッシュ」だけで陳腐化が起きない
    （他人の操作が owner のリストに影響しない）。詳細は PLAN.md / KNOWLEDGE.md。
    """
    owner = x_user.strip().lower()
    if not owner:
        raise HTTPException(status_code=400, detail="X-User is required")

    cache_key = f"friends:{owner}"
    cached = store.cache.get(cache_key)
    if cached is not None:
        return {"friends": json.loads(cached), "cached": True}

    # miss: owner 単一パーティション・クエリで友達を時系列に並べる。
    items = list(
        store.friends_container.query_items(
            query="SELECT * FROM c WHERE c.owner=@owner ORDER BY c.createdAt ASC",
            parameters=[{"name": "@owner", "value": owner}],
            partition_key=owner,
        )
    )
    friends = [item["friend"] for item in items]
    store.cache.set(cache_key, json.dumps(friends), ex=config.CACHE_TTL_SECONDS)
    return {"friends": friends, "cached": False}
