"""可観測性 (Observability) を体感するための、CPU を意図的に動かせる小さな API。

このプロジェクトの主役は「アプリのコード」ではなく **監視 (Container Insights /
マネージド Prometheus + Grafana)**。アプリ側は、ダッシュボードのグラフを意図的に
動かすための「負荷つまみ」を持つだけ。

- どの Pod が応答したか分かるよう、レスポンスに **pod 名 (HOSTNAME)** を載せる
  → スケールアウトで応答 Pod が増える様子を体感できる。
- `/work`  : リクエスト中に **同期的に CPU を焼く** (ms 指定)。負荷生成器から多重に
             叩くと Service が全 Pod に分散し、平均 CPU が上がって **HPA が発火**する。
- `/burn`  : **この Pod だけ**をバックグラウンドで N 秒焼く。Grafana で「特定 Pod の
             CPU 線だけが跳ねる」様子を見るのに使う。
- `/crash` : プロセスを落とす → liveness 失敗で kubelet が再起動 → 監視の
             **再起動回数 (restartCount)** が増えるのを観察する。
"""
import os
import socket
import threading
import time

from flask import Flask, jsonify, request

app = Flask(__name__)

# イメージに焼き込まれるバージョン (どの版が応答したか分かるように)。
APP_VERSION = os.environ.get("APP_VERSION", "dev")
# k8s は Pod 名を HOSTNAME に入れる。スケールアウトの可視化に使う。
POD_NAME = os.environ.get("HOSTNAME", socket.gethostname())
START = time.monotonic()


def burn_until(deadline: float) -> float:
    """deadline (monotonic 秒) まで CPU を回し続けるだけのループ。

    Python の GIL があるので 1 スレッドで使い切れるのは概ね 1 コア分。
    HPA の閾値 (requests.cpu の 50%) を超えさせるには十分。
    """
    x = 0.0001
    while time.monotonic() < deadline:
        # 中身に意味は無い。最適化で消えないよう結果を持ち回るだけ。
        x = x * 1.0000001 + 1.0
    return x


@app.get("/")
@app.get("/api")
def info():
    return jsonify(
        version=APP_VERSION,
        pod=POD_NAME,                       # どの Pod が応答したか
        uptime_sec=round(time.monotonic() - START, 1),
        hint="/work?ms=50 で負荷, /burn?seconds=30 で単一Pod負荷, /crash で再起動",
    )


@app.get("/healthz")
def healthz():
    # liveness/readiness 用。監視プロジェクトでは probe 自体は壊さない。
    return "ok", 200


@app.get("/work")
def work():
    """リクエスト中に同期的に CPU を焼く。負荷生成器から多重に叩いて使う。

    同期処理なので gunicorn の worker を ms ミリ秒占有する。多数の同時リクエストが
    Service 経由で全 Pod に分散 → 平均 CPU が上がり HPA が発火する。
    """
    ms = max(0, min(int(request.args.get("ms", "50")), 2000))
    burn_until(time.monotonic() + ms / 1000.0)
    return jsonify(pod=POD_NAME, version=APP_VERSION, burned_ms=ms)


@app.get("/burn")
def burn():
    """この Pod だけをバックグラウンドで seconds 秒焼く (応答は即返す)。

    Grafana で「狙った 1 Pod の CPU 線だけが跳ねる」のを見るための実験用。
    """
    seconds = max(1, min(int(request.args.get("seconds", "30")), 600))
    threads = max(1, min(int(request.args.get("threads", "1")), 8))
    deadline = time.monotonic() + seconds
    for _ in range(threads):
        threading.Thread(target=burn_until, args=(deadline,), daemon=True).start()
    return jsonify(pod=POD_NAME, version=APP_VERSION, burning_seconds=seconds, threads=threads)


@app.get("/crash")
def crash():
    """プロセスを落として「Pod の再起動」を起こす。

    監視ダッシュボードで restartCount や再起動イベントが増えるのを観察する実験用。
    すぐ落とすと応答が返らないので、少し待ってから os._exit する。
    """
    def die():
        time.sleep(0.2)
        os._exit(1)

    threading.Thread(target=die, daemon=True).start()
    return jsonify(pod=POD_NAME, message="0.2 秒後にこの Pod を落とします")


if __name__ == "__main__":
    # ローカル実行用。コンテナでは gunicorn 経由で起動する。
    app.run(host="0.0.0.0", port=8080)
