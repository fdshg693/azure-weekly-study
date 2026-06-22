"""Cosmos DB と Redis へのアクセスをまとめる薄いラッパ。

FastAPI(読み取り) と Functions(書き込み) で同じ考え方を使うが、独立デプロイのため
コードは各アプリに持たせている（共有パッケージにはしない）。ここは読み取り側。
"""
import urllib3

from azure.cosmos import CosmosClient, PartitionKey
import redis

import config

# Emulator の自己署名証明書で出る警告を黙らせる（検証を切っている前提）
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def pair_key(user_a: str, user_b: str) -> str:
    """2 人の username を辞書順ソートして連結。会話のパーティションキー。"""
    a, b = sorted([user_a, user_b])
    return f"{a}__{b}"


def shape_message(doc: dict) -> dict:
    """Cosmos ドキュメントから、フロントが必要とするフィールドだけ取り出す。
    （_rid / _ts などの Cosmos システムフィールドを落とす）。"""
    return {
        "id": doc["id"],
        "from": doc["from"],
        "to": doc["to"],
        "text": doc["text"],
        "createdAt": doc["createdAt"],
    }


# --- Cosmos ----------------------------------------------------------------
_cosmos = CosmosClient(
    url=config.COSMOS_ENDPOINT,
    credential=config.COSMOS_KEY,
    connection_verify=config.COSMOS_VERIFY_TLS,
)


def init_cosmos():
    """DB / コンテナが無ければ作る（ローカル初回や検証用に冪等化）。"""
    db = _cosmos.create_database_if_not_exists(id=config.COSMOS_DB)
    db.create_container_if_not_exists(
        id="users", partition_key=PartitionKey(path="/id")
    )
    db.create_container_if_not_exists(
        id="messages", partition_key=PartitionKey(path="/pairKey")
    )
    # V2: 友達リスト。owner（リストの持ち主）でパーティション分割し、
    # 一覧取得を単一パーティション・クエリにする（conversation の pairKey と同じ発想）。
    db.create_container_if_not_exists(
        id="friends", partition_key=PartitionKey(path="/owner")
    )
    return db


_db = init_cosmos()
users_container = _db.get_container_client("users")
messages_container = _db.get_container_client("messages")
friends_container = _db.get_container_client("friends")


# --- Redis -----------------------------------------------------------------
cache = redis.Redis(
    host=config.REDIS_HOST,
    port=config.REDIS_PORT,
    password=config.REDIS_PASSWORD,
    ssl=config.REDIS_SSL,
    decode_responses=True,  # str で読み書きする
)
