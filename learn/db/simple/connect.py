"""ローカルから マネージド PostgreSQL に繋ぎ、最小の CRUD を一周するスクリプト。

db トピック PLAN Step 1 の「接続の最小ループ」を担う。
- .env (または環境変数) から接続情報を読む (シンプルな .env 読込を自前で実装)。
- 接続 → テーブル作成 → INSERT → SELECT → 件数表示、までを 1 回で確認する。

「因果を確かめる」実験での使い方:
  just allow-my-ip  → このスクリプトが成功する (自分の IP がファイアウォール許可)。
  just deny-my-ip   → 接続が拒否され、ここで例外 (タイムアウト/接続不可) になる。
「マネージド DB はデフォルトで閉じている」「許可 IP を出し入れすると到達が変わる」
を、レスポンスの成否で体感する。
"""
import os
import sys
from pathlib import Path


def load_env() -> None:
    """同じフォルダの .env を読み、未設定の環境変数だけ補う。

    優先順位は「既存の環境変数 > .env」。python-dotenv を使わず、
    KEY=VALUE 形式だけを最小限パースする (リポジトリ共通の方針: シンプルな .env)。
    """
    env_path = Path(__file__).with_name(".env")
    if not env_path.exists():
        return
    for raw in env_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip()
        # 既に環境変数で与えられていれば、そちらを尊重する。
        os.environ.setdefault(key, value)


def build_conn_str() -> str:
    """psycopg 用の接続文字列を組み立てる。必須値が無ければ即エラーにする。"""
    host = os.environ.get("PGHOST", "")
    user = os.environ.get("PGUSER", "")
    password = os.environ.get("PGPASSWORD", "")
    dbname = os.environ.get("PGDATABASE", "postgres")
    sslmode = os.environ.get("PGSSLMODE", "require")

    missing = [k for k, v in {"PGHOST": host, "PGUSER": user, "PGPASSWORD": password}.items() if not v]
    if missing:
        print(f"必須の接続情報がありません: {', '.join(missing)}", file=sys.stderr)
        print("`just init-env` と `just deploy` を先に実行してください。", file=sys.stderr)
        sys.exit(1)

    return (
        f"host={host} port=5432 dbname={dbname} "
        f"user={user} password={password} sslmode={sslmode} "
        # 拒否時にいつまでも待たないよう短めのタイムアウトを付ける (実験の観察用)。
        f"connect_timeout=10"
    )


def main() -> None:
    import psycopg

    load_env()
    conn_str = build_conn_str()
    host = os.environ.get("PGHOST")
    print(f"接続を試行: {host}")

    # 接続できなければここで例外 → deny-my-ip の状態だと到達できない事を体感する。
    with psycopg.connect(conn_str) as conn:
        with conn.cursor() as cur:
            # 1) サーバー情報 — 「サーバー > データベース > ロール」の階層を確認。
            cur.execute("select version(), current_database(), current_user")
            version, current_db, current_user = cur.fetchone()
            print("接続成功")
            print(f"  version       : {version.split(',')[0]}")
            print(f"  database      : {current_db}")
            print(f"  login user    : {current_user}")

            # 2) テーブル作成 (冪等)。
            cur.execute(
                """
                create table if not exists visits (
                    id   serial primary key,
                    note text not null,
                    at   timestamptz not null default now()
                )
                """
            )

            # 3) INSERT — 実行のたびに 1 行増えるので「操作で結果が変わる」を体感。
            cur.execute(
                "insert into visits (note) values (%s) returning id, at",
                ("hello from local",),
            )
            new_id, at = cur.fetchone()
            print(f"  inserted      : id={new_id} at={at}")

            # 4) SELECT — 直近 5 件と総件数を表示。
            cur.execute("select id, note, at from visits order by id desc limit 5")
            rows = cur.fetchall()
            cur.execute("select count(*) from visits")
            (total,) = cur.fetchone()
            print(f"  total rows    : {total}")
            print("  recent rows   :")
            for rid, note, ts in rows:
                print(f"    - #{rid} {note} ({ts})")

        conn.commit()


if __name__ == "__main__":
    main()
