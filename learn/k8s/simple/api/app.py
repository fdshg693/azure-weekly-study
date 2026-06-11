"""最小の API サーバ。

- /healthz : liveness/readiness probe 用。DB に依存せず常に 200 を返す。
- /api     : 動作確認用。Secret 由来の env で PostgreSQL に接続し結果を返す。
- /api/db  : DB 接続チェックのみを JSON で返す。

DB 接続情報は Kubernetes Secret (db-conn) から envFrom で環境変数として渡る:
  PGHOST / PGUSER / PGPASSWORD / PGDATABASE / PGSSLMODE
"""
import os

from flask import Flask, jsonify

app = Flask(__name__)


def db_check():
    """PostgreSQL へ接続し version() を取得する。失敗しても例外にせず結果を返す。"""
    try:
        import psycopg

        conn_str = (
            f"host={os.environ['PGHOST']} "
            f"port=5432 "
            f"dbname={os.environ.get('PGDATABASE', 'postgres')} "
            f"user={os.environ['PGUSER']} "
            f"password={os.environ['PGPASSWORD']} "
            f"sslmode={os.environ.get('PGSSLMODE', 'require')}"
        )
        with psycopg.connect(conn_str, connect_timeout=5) as conn:
            with conn.cursor() as cur:
                cur.execute("select version()")
                version = cur.fetchone()[0]
        return {"connected": True, "version": version}
    except KeyError as exc:
        return {"connected": False, "error": f"missing env var: {exc}"}
    except Exception as exc:  # noqa: BLE001 - POC なので握りつぶして表示する
        return {"connected": False, "error": str(exc)}


@app.get("/healthz")
def healthz():
    # probe 用。DB の状態に関係なくプロセスが生きていれば 200。
    return "ok", 200


@app.get("/api")
def api_root():
    return jsonify(message="hello from api", db=db_check())


@app.get("/api/db")
def api_db():
    return jsonify(db_check())


if __name__ == "__main__":
    # ローカル実行用。コンテナでは gunicorn 経由で起動する。
    app.run(host="0.0.0.0", port=8080)
