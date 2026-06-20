"""テンプレート化 (Helm / Kustomize) と環境差分を体感するための最小 API。

このプロジェクトの主役は「マニフェストのパッケージ化」と「環境ごとの出し分け」。
config-rollout までと違い DB などの周辺は持たず、env に出る違いだけに集中する:

- APP_VERSION : Dockerfile の ARG→ENV で焼き込む不変のイメージ識別子。
- APP_ENV     : ConfigMap / Helm values で渡す「環境名」(dev / prod)。
                overlay や values-*.yaml を変えるとここが切り替わる。
- APP_MESSAGE : 同上。環境ごとに差し替える非機密メッセージ。

front はこの値を 1 秒ごとに取得して、dev と prod で応答が変わること、
prod では複数レプリカ (pod 名が入れ替わる) ことを目視できる。
"""
import os
import socket

from flask import Flask, jsonify

app = Flask(__name__)

# イメージタグごとに焼き込まれる不変の版。dev/prod で同じイメージを使い、
# 違いは「設定 (env)」と「台数/リソース」だけに出る、という設計を強調する。
APP_VERSION = os.environ.get("APP_VERSION", "dev")


@app.get("/healthz")
def healthz():
    # liveness / readiness 用。設定に依存せず常に 200。
    return "ok", 200


@app.get("/api")
def api_root():
    return jsonify(
        {
            "version": APP_VERSION,                          # イメージに焼き込まれた版
            "env": os.environ.get("APP_ENV", "(unset)"),     # overlay / values で差し替え
            "message": os.environ.get("APP_MESSAGE", "(unset)"),
            "pod": socket.gethostname(),                     # どの Pod が応答したか (レプリカ数の違いが見える)
        }
    )


if __name__ == "__main__":
    # ローカル実行用。コンテナでは gunicorn 経由で起動する。
    app.run(host="0.0.0.0", port=8080)
