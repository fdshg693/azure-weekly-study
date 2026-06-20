"""ConfigMap とローリングアップデートを体感するための API。

このプロジェクトの主役は「設定の出どころ」と「バージョンの入れ替え」:

- 非機密の挙動 (メッセージ・特徴フラグ) は **ConfigMap (app-config)** から env で受け取る。
  → APP_MESSAGE / FEATURE_GREETING
- 機密の DB 接続情報は **Secret (db-conn)** から env で受け取る (simple と同じ仕組み)。
  → PGHOST / PGUSER / PGPASSWORD / PGDATABASE / PGSSLMODE
- 「どのイメージ (v1 / v2) が動いているか」は Dockerfile の ARG→ENV で焼き込む。
  → APP_VERSION。ロールアウト中にこの値が切り替わるのを観察できる。
- readiness probe を故意に壊す実験用フラグ。
  → BREAK_HEALTH=true なら /healthz が 500 を返し、新 Pod が Ready にならず
    ロールアウトが止まる (古い Pod が生き残る) ことを確認できる。
"""
import os

from flask import Flask, jsonify

app = Flask(__name__)

# --- ビルド時に焼き込まれる「不変」の情報 (イメージタグごとに変わる) ---
APP_VERSION = os.environ.get("APP_VERSION", "dev")
# "true" のときだけ /healthz を 500 にして、壊れた v2 のロールアウトを再現する。
BREAK_HEALTH = os.environ.get("BREAK_HEALTH", "false").lower() == "true"


def db_check():
    """PostgreSQL へ接続し version() を取得する。失敗しても握りつぶして結果を返す。

    接続情報は Secret(db-conn) 由来の env。simple プロジェクトで作った
    PostgreSQL をそのまま流用する (機密 = Secret の置き場という対比のため)。
    """
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


def build_payload():
    """ConfigMap 由来の env を読んでレスポンスを組み立てる。

    Pod の env は起動時に固定される。ConfigMap を書き換えても Pod を入れ替える
    (rollout restart) まで反映されない、という因果をここで体感する。
    """
    # ConfigMap (app-config) から。無ければ既定値。
    message = os.environ.get("APP_MESSAGE", "(APP_MESSAGE 未設定)")
    feature_greeting = os.environ.get("FEATURE_GREETING", "off").lower() == "on"

    payload = {
        "version": APP_VERSION,          # どのイメージが応答したか
        "message": message,              # ConfigMap で差し替え可能な非機密メッセージ
        "feature_greeting": feature_greeting,
        "db": db_check(),                # Secret 由来で DB 疎通
    }
    # 特徴フラグが on のときだけ追加フィールドを返す (ConfigMap で挙動が変わる例)。
    if feature_greeting:
        payload["greeting"] = "ようこそ！ (FEATURE_GREETING=on)"
    # v2 系イメージだけが返す新フィールド (ロールアウトで増える様子を観察する例)。
    if APP_VERSION.startswith("v2"):
        payload["new_in_v2"] = "v2 で追加されたフィールド"
    return payload


@app.get("/healthz")
def healthz():
    # probe 用。通常は DB に依存せず 200。BREAK_HEALTH=true のときだけ 500 を返し、
    # readiness 失敗 → 新 Pod が Ready にならず rollout が止まる様子を再現する。
    if BREAK_HEALTH:
        return "intentionally broken", 500
    return "ok", 200


@app.get("/api")
def api_root():
    return jsonify(build_payload())


@app.get("/api/db")
def api_db():
    return jsonify(db_check())


if __name__ == "__main__":
    # ローカル実行用。コンテナでは gunicorn 経由で起動する。
    app.run(host="0.0.0.0", port=8080)
