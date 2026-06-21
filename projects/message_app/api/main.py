"""読み取り API（FastAPI / App Service 想定）。

責務は「読み取り」のみ：login(upsert) / users 一覧 / conversation 取得。
すべて Redis を read-through キャッシュとして経由する（miss 時だけ Cosmos）。
メッセージ送信(書き込み)は Functions 側が担当する。
"""
import json
from datetime import datetime, timezone

from fastapi import FastAPI, Header, HTTPException, Query
from pydantic import BaseModel

import config
import store

app = FastAPI(title="message_app read API")


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class LoginBody(BaseModel):
    username: str


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/login")
def login(body: LoginBody):
    """username で upsert（無ければ作る = サインアップ兼ログイン）。"""
    username = body.username.strip().lower()
    if not username:
        raise HTTPException(status_code=400, detail="username is required")

    store.users_container.upsert_item(
        {"id": username, "username": username, "createdAt": _now_iso()}
    )
    # 新規ユーザーが増えたので users 一覧キャッシュを破棄（次回 miss で再構築）
    store.cache.delete("users:all")
    return {"username": username}


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
