"""メッセージ送信処理（Azure Functions / Python v2 プログラミングモデル）。

書き込みだけを担う Serverless エンドポイント。
- POST /api/messages  body: { "to": "<相手>", "text": "<本文>" }  header: X-User: <送信者>
- Cosmos の messages に append（正本を更新）
- 送信者のキャッシュ conv:{from}:{pairKey} **だけ** を更新（受信者は陳腐化＝学習ポイント）
"""
import json
import uuid
from datetime import datetime, timezone

import azure.functions as func

import store

app = func.FunctionApp()


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
