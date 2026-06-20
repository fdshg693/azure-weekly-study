"""Container Apps Job が「1 回起動して終了する」ことを体験するためのワーカー。

サーバー（常駐プロセス）ではなく、起動 → 仕事 → 終了 が 1 回の "実行 (execution)"。
このスクリプトは:

  1. 起動時刻・実行回数の手がかり・設定値を 1 行ログに出す（標準出力 → Log Analytics へ）
  2. 数秒「仕事をしているふり」をする
  3. FAIL_JOB=true なら異常終了 (exit 1)、そうでなければ正常終了 (exit 0)

終了コードが Job の成否（Succeeded / Failed）になり、Failed だと
replicaRetryLimit の回数だけリトライされる、という因果を体験するのが狙い。

環境変数（Job 側の template.containers[].env で注入。ローカルでは同階層の .env でも可）:
  JOB_MESSAGE : ログに出す任意メッセージ
  WORK_SECONDS: 「仕事」にかける秒数（既定 3）
  FAIL_JOB    : "true" のとき exit 1 で失敗させる（リトライ観察用）
"""

import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def load_dotenv() -> None:
    """依存を増やさず、同階層に .env があれば KEY=VALUE を環境変数へ流し込む。

    Job 実行時は Azure 側の env が使われるので .env は不要。ローカルで
    `python worker.py` を試すときの利便用。既存の環境変数は上書きしない。
    """
    env_path = Path(__file__).with_name(".env")
    if not env_path.exists():
        return
    for raw in env_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip())


def main() -> int:
    load_dotenv()

    message = os.environ.get("JOB_MESSAGE", "hello from container apps job")
    work_seconds = int(os.environ.get("WORK_SECONDS", "3"))
    fail = os.environ.get("FAIL_JOB", "false").lower() == "true"

    # Container Apps が実行ごとに割り当てる識別子。複数レプリカ実行時に区別できる。
    replica = os.environ.get("CONTAINER_APP_REPLICA_NAME", "local")
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")

    print(f"[{now}] start replica={replica} message='{message}' "
          f"work={work_seconds}s fail={fail}", flush=True)

    time.sleep(work_seconds)

    if fail:
        print(f"[{now}] FAILED on purpose (FAIL_JOB=true) -> exit 1", flush=True)
        return 1

    print(f"[{now}] done -> exit 0", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
