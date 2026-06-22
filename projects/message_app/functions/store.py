"""Functions(書き込み側)用の Cosmos / Redis アクセス。

設定は Functions の環境変数(local.settings.json / App Settings)から読む。
FastAPI 側の store.py と思想は同じだが、独立デプロイのため別ファイルにしている。
"""
import os

import urllib3

from azure.cosmos import CosmosClient, PartitionKey
import redis

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def _bool(name: str, default: bool) -> bool:
    val = os.getenv(name)
    if val is None:
        return default
    return val.strip().lower() in ("1", "true", "yes", "on")


COSMOS_ENDPOINT = os.getenv("COSMOS_ENDPOINT", "https://localhost:8081")
COSMOS_KEY = os.getenv(
    "COSMOS_KEY",
    "C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==",
)
COSMOS_DB = os.getenv("COSMOS_DB", "messageapp")
COSMOS_VERIFY_TLS = _bool("COSMOS_VERIFY_TLS", False)
CACHE_TTL_SECONDS = int(os.getenv("CACHE_TTL_SECONDS", "60"))


def pair_key(user_a: str, user_b: str) -> str:
    a, b = sorted([user_a, user_b])
    return f"{a}__{b}"


def shape_message(doc: dict) -> dict:
    """Cosmos ドキュメントからフロントが必要なフィールドだけ取り出す。"""
    return {
        "id": doc["id"],
        "from": doc["from"],
        "to": doc["to"],
        "text": doc["text"],
        "createdAt": doc["createdAt"],
    }


_cosmos = CosmosClient(
    url=COSMOS_ENDPOINT, credential=COSMOS_KEY, connection_verify=COSMOS_VERIFY_TLS
)
_db = _cosmos.create_database_if_not_exists(id=COSMOS_DB)
# V2: users はサインアップ/検証で書き込むのでハンドルを保持する。
users_container = _db.create_container_if_not_exists(
    id="users", partition_key=PartitionKey(path="/id")
)
messages_container = _db.create_container_if_not_exists(
    id="messages", partition_key=PartitionKey(path="/pairKey")
)
# V2: 友達リスト。owner でパーティション分割（読み取り側 store.py と同じ）。
friends_container = _db.create_container_if_not_exists(
    id="friends", partition_key=PartitionKey(path="/owner")
)

cache = redis.Redis(
    host=os.getenv("REDIS_HOST", "localhost"),
    port=int(os.getenv("REDIS_PORT", "6379")),
    password=os.getenv("REDIS_PASSWORD") or None,
    ssl=_bool("REDIS_SSL", False),
    decode_responses=True,
)
