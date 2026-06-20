"""Workload Identity による「パスワードレス」DB 接続を体感するための API。

このプロジェクトの主役は **キーレス化**:
config-rollout までは DB 接続を Secret(db-conn) のパスワードで行っていた。
ここでは **パスワードを一切持たず**、Pod に紐づいた Microsoft Entra の
トークンで PostgreSQL に接続する。

仕組み (env は何も機密を持たない点に注目):
- PGHOST / PGUSER / PGDATABASE … 接続先と「誰として入るか」だけ。機密ではない。
- パスワードの代わりに、Azure AD のアクセストークンを毎回取得して渡す。
  - トークン取得は azure-identity の DefaultAzureCredential。
  - Workload Identity の webhook が Pod に注入する env
    (AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_FEDERATED_TOKEN_FILE /
     AZURE_AUTHORITY_HOST) を使って、ServiceAccount のトークンを
     User-Assigned Managed Identity のトークンに「交換」してくれる。
  - だからコードにも env にもシークレットが無い (= キーレス)。

「因果を確かめる」実験:
PostgreSQL 側で、この Managed Identity の Entra 管理者ロールを外す (just role-off) と
トークンは取れても DB がログインを拒否する → connected:false に変わる。
付け直す (just role-on) と connected:true に戻る。ロールで挙動が変わる感覚を k8s に持ち込む。
"""
import os

from flask import Flask, jsonify

app = Flask(__name__)

# PostgreSQL フレキシブルサーバーの Entra 認証で使う固定スコープ。
# このスコープのアクセストークンが、DB ログインの「パスワード」になる。
PG_AAD_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"


def get_access_token():
    """Workload Identity 経由でアクセストークンを取得する。

    DefaultAzureCredential は、Pod に注入された Workload Identity の env を
    見つけると WorkloadIdentityCredential として動作する。ローカルで az login
    済みなら AzureCliCredential にフォールバックするので開発時も動く。
    """
    from azure.identity import DefaultAzureCredential

    credential = DefaultAzureCredential()
    return credential.get_token(PG_AAD_SCOPE).token


def db_check():
    """Entra トークンを「パスワード」として PostgreSQL に接続し version() を取る。

    失敗しても握りつぶし、error を返して原因が見えるようにする (実験用)。
    """
    try:
        import psycopg

        # ここがキモ: password にシークレットではなく毎回発行のトークンを渡す。
        token = get_access_token()
        conn_str = (
            f"host={os.environ['PGHOST']} "
            f"port=5432 "
            f"dbname={os.environ.get('PGDATABASE', 'postgres')} "
            f"user={os.environ['PGUSER']} "          # = Managed Identity の名前
            f"password={token} "                       # = Entra アクセストークン
            f"sslmode={os.environ.get('PGSSLMODE', 'require')}"
        )
        with psycopg.connect(conn_str, connect_timeout=5) as conn:
            with conn.cursor() as cur:
                cur.execute("select current_user, version()")
                current_user, version = cur.fetchone()
        return {"connected": True, "login_user": current_user, "version": version}
    except KeyError as exc:
        return {"connected": False, "error": f"missing env var: {exc}"}
    except Exception as exc:  # noqa: BLE001 - POC なので握りつぶして表示する
        # ロールを外した直後はここで「認証失敗」系のエラーが出る (因果実験の観察点)。
        return {"connected": False, "error": str(exc)}


def build_payload():
    # env に password が無いことを示すため、見えている接続関連 env を列挙する
    # (PGPASSWORD は存在しない = キーレスである証拠)。
    visible_env = {
        k: os.environ.get(k)
        for k in ("PGHOST", "PGUSER", "PGDATABASE", "AZURE_CLIENT_ID")
    }
    return {
        "auth_mode": "workload-identity (passwordless)",
        "has_pgpassword_env": "PGPASSWORD" in os.environ,  # 期待値: false
        "env": visible_env,
        "db": db_check(),
    }


@app.get("/healthz")
def healthz():
    # probe 用。DB の状態に依存させない (DB ロールを外しても Pod は生かしておき、
    # connected が false に変わる様子を観察したいため)。
    return "ok", 200


@app.get("/api")
def api_root():
    return jsonify(build_payload())


@app.get("/api/db")
def api_db():
    return jsonify(db_check())


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
