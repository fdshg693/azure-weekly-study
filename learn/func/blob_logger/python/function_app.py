import datetime
import logging
import os

import azure.functions as func  # type: ignore

app = func.FunctionApp()

# コンテナ名は app_settings（Terraform で設定）から取得する。
# 未設定でもローカルで動くよう、既定値を用意しておく。
UPLOADS_CONTAINER = os.environ.get("UPLOADS_CONTAINER", "uploads")
LOGS_CONTAINER = os.environ.get("LOGS_CONTAINER", "logs")


# ============================================================================
# Blob トリガー: uploads コンテナへのアップロードを検知してログを書き出す
# ============================================================================
# 仕組み:
#   - @app.blob_trigger : uploads/{name} に Blob が作成/更新されると発火する。
#       {name} はファイル名にマッチするバインディング式で、出力先の名前にも使える。
#   - @app.blob_output  : logs/{name}.log に「別ファイル」としてログを書き出す。
#       出力先を別コンテナ（logs）にしているのが重要。トリガー対象（uploads）と
#       同じコンテナに書くと、書いたログ自身が再び発火して無限ループになる。
#
# 接続: いずれも "AzureWebJobsStorage"（Function ランタイムのストレージ接続文字列）。
#       Terraform 側で Storage Account をランタイムストレージに指定しているため、
#       追加の接続設定なしで入力（uploads）も出力（logs）も同じアカウントを使える。
#
# ポイント: 関数コードは Blob を「読む」「書く」処理を一切書いていない。
#           入出力はすべてバインディングがやってくれるので、ロジックは
#           「ログ文字列を組み立てて Out に set するだけ」になる。
@app.blob_trigger(
    arg_name="blob",
    path=f"{UPLOADS_CONTAINER}/{{name}}",
    connection="AzureWebJobsStorage",
)
@app.blob_output(
    arg_name="logblob",
    path=f"{LOGS_CONTAINER}/{{name}}.log",
    connection="AzureWebJobsStorage",
)
def log_upload(blob: func.InputStream, logblob: func.Out[str]) -> None:
    # blob.name は "uploads/<ファイル名>" のようにコンテナ名込みのフルパス。
    # blob.length はアップロードされたファイルのバイト数。
    logging.info("blob trigger fired: name=%s size=%s bytes", blob.name, blob.length)

    # UTC のタイムスタンプ付きでログ 1 行を組み立てる
    timestamp = datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z"
    log_line = (
        f"[{timestamp}] uploaded blob='{blob.name}' "
        f"size={blob.length} bytes\n"
    )

    # logs コンテナへ "<元のファイル名>.log" として書き出す
    logblob.set(log_line)

    logging.info("wrote log to %s container", LOGS_CONTAINER)
