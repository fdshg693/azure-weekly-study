"""環境変数 / .env から設定値を読む。

ローカル(Cosmos Emulator + docker redis)と Azure(Cosmos + Azure Cache for Redis)を
同じコードで切り替えられるよう、接続先はすべて環境変数で受け取る。
"""
import os

from dotenv import load_dotenv

# プロジェクト直下の .env を読む（無ければ環境変数のみ）
load_dotenv()


def _bool(name: str, default: bool) -> bool:
    val = os.getenv(name)
    if val is None:
        return default
    return val.strip().lower() in ("1", "true", "yes", "on")


# --- Cosmos DB -------------------------------------------------------------
# 既定値は Cosmos DB Emulator の公開（well-known）エンドポイント / キー。
COSMOS_ENDPOINT = os.getenv("COSMOS_ENDPOINT", "https://localhost:8081")
COSMOS_KEY = os.getenv(
    "COSMOS_KEY",
    "C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==",
)
COSMOS_DB = os.getenv("COSMOS_DB", "messageapp")
# Emulator は自己署名証明書なので TLS 検証を切る。Azure 本番では true に。
COSMOS_VERIFY_TLS = _bool("COSMOS_VERIFY_TLS", False)

# --- Redis -----------------------------------------------------------------
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD") or None
# Azure Cache for Redis は TLS 必須(6380)。ローカル docker redis は false(6379)。
REDIS_SSL = _bool("REDIS_SSL", False)

# キャッシュ TTL（秒）。短めにして陳腐化→回復を体験しやすくする。
CACHE_TTL_SECONDS = int(os.getenv("CACHE_TTL_SECONDS", "60"))
