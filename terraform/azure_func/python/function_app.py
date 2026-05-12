import json
import logging
import os
import random
import time
import urllib.error
import urllib.request

import azure.functions as func  # type: ignore

app = func.FunctionApp()


# ============================================================================
# 既存: 同期エンドポイント（残しておく — 比較用）
# ============================================================================
@app.route(route="random", auth_level=func.AuthLevel.ANONYMOUS, methods=["GET"])
def random_number(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("random_number function processed a request.")

    try:
        lo = int(req.params.get("min", "1"))
        hi = int(req.params.get("max", "100"))
    except ValueError:
        return func.HttpResponse(
            "min/max must be integers",
            status_code=400,
            mimetype="text/plain",
        )

    if lo > hi:
        lo, hi = hi, lo

    value = random.randint(lo, hi)

    # HTMX が innerHTML としてそのまま差し込めるよう HTML 断片で返す
    return func.HttpResponse(
        f"<span>{value}</span>",
        status_code=200,
        mimetype="text/html",
    )


# ============================================================================
# 非同期プロキシ: ブラウザ → このプロキシ → Logic App → SB → Worker → Table
# ============================================================================
# 案B のために用意した薄いプロキシ。
#   - 静的ページ（HTMX）からは同一オリジン CORS の Function を叩く方が簡単
#   - Logic App の callback URL（SAS 署名付き）をブラウザに漏らさずに済む
#   - Logic App 側に CORS 設定を入れなくて済む
# 戻り値は HTMX が innerHTML に差し込める HTML 断片。
@app.route(route="async-random", auth_level=func.AuthLevel.ANONYMOUS, methods=["GET"])
def async_random(req: func.HttpRequest) -> func.HttpResponse:
    try:
        lo = int(req.params.get("min", "1"))
        hi = int(req.params.get("max", "100"))
    except ValueError:
        return func.HttpResponse(
            "<span>min/max must be integers</span>",
            status_code=400,
            mimetype="text/html",
        )
    if lo > hi:
        lo, hi = hi, lo

    callback_url = os.environ.get("LOGIC_APP_CALLBACK_URL")
    if not callback_url:
        return func.HttpResponse(
            "<span>LOGIC_APP_CALLBACK_URL is not configured</span>",
            status_code=500,
            mimetype="text/html",
        )

    payload = json.dumps({"min": lo, "max": hi}).encode("utf-8")
    http_req = urllib.request.Request(
        callback_url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    # Logic App は Worker のスリープ + Until ポーリングが直列で乗るので
    # クライアントへの応答時間 ≒ worker_sleep_seconds + 数秒（PT3S × 数回 + α）。
    # 余裕を見て 90 秒待つ（Functions Consumption の最大 230 秒には十分収まる）。
    try:
        with urllib.request.urlopen(http_req, timeout=90) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        logging.exception("async_random: Logic App returned HTTP error")
        return func.HttpResponse(
            f"<span>Logic App HTTP error: {e.code}</span>",
            status_code=502,
            mimetype="text/html",
        )
    except urllib.error.URLError as e:
        logging.exception("async_random: Logic App request failed")
        return func.HttpResponse(
            f"<span>Logic App request failed: {e.reason}</span>",
            status_code=502,
            mimetype="text/html",
        )

    value = body.get("value")
    job_id = str(body.get("jobId", ""))
    short_id = job_id[:8] if job_id else ""
    return func.HttpResponse(
        f'<span>{value} <small style="color:#888">(jobId: {short_id}…)</small></span>',
        status_code=200,
        mimetype="text/html",
    )


# ============================================================================
# ワーカー: Service Bus キュー "jobs" を受信し、わざと寝てから乱数を返す
# ============================================================================
# Logic App から enqueue されたジョブを受け取り、
#   1. WORKER_SLEEP_SECONDS だけスリープ（学習用に「重い処理」を模擬）
#   2. min/max の範囲で乱数を生成
#   3. Table Storage "results" に {jobId, value, status=done} を書き込む
#
# 接続:
#   - ServiceBusConnection: Service Bus namespace の接続文字列（Terraform で注入）
#   - AzureWebJobsStorage:  Functions ランタイムが使う Storage（テーブル出力もここに同居）
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="jobs",
    connection="ServiceBusConnection",
)
@app.table_output(
    arg_name="entity",
    table_name="results",
    connection="AzureWebJobsStorage",
)
def worker(msg: func.ServiceBusMessage, entity: func.Out[str]) -> None:
    payload = json.loads(msg.get_body().decode("utf-8"))
    job_id = payload["jobId"]
    lo = int(payload.get("min", 1))
    hi = int(payload.get("max", 100))
    if lo > hi:
        lo, hi = hi, lo

    sleep_seconds = float(os.environ.get("WORKER_SLEEP_SECONDS", "5"))
    logging.info(
        "worker: received jobId=%s min=%d max=%d, sleeping %.1fs",
        job_id,
        lo,
        hi,
        sleep_seconds,
    )
    time.sleep(sleep_seconds)

    value = random.randint(lo, hi)
    logging.info("worker: jobId=%s value=%d (writing to table)", job_id, value)

    # Table Storage の出力バインディングは「JSON 文字列」を渡す。
    # PartitionKey/RowKey が必須。RowKey に jobId を入れて後から引ける形にする。
    entity.set(
        json.dumps(
            {
                "PartitionKey": "job",
                "RowKey": job_id,
                "status": "done",
                "value": value,
            }
        )
    )


# ============================================================================
# ステータス確認: Logic App の Until ループから呼ばれる
# ============================================================================
# GET /api/status?jobId=<guid>
#
# 動作:
#   - Table Storage に該当行があれば 200 {"status": "done", "value": N}
#   - まだ無ければ 200 {"status": "pending"}  ← 404 ではなく 200 を返すのがポイント
#     （Logic App の Until は条件式で判定するため、HTTP エラーで止めない方が扱いやすい）
@app.route(route="status", auth_level=func.AuthLevel.ANONYMOUS, methods=["GET"])
@app.table_input(
    arg_name="row",
    table_name="results",
    partition_key="job",
    row_key="{Query.jobId}",
    connection="AzureWebJobsStorage",
)
def status(req: func.HttpRequest, row: str) -> func.HttpResponse:
    job_id = req.params.get("jobId")
    if not job_id:
        return func.HttpResponse(
            json.dumps({"error": "jobId is required"}),
            status_code=400,
            mimetype="application/json",
        )

    # table_input は「該当行が無い」場合 None/空文字を渡してくる。
    # row が来ていれば JSON 化された行エンティティ（文字列）。
    if not row:
        return func.HttpResponse(
            json.dumps({"status": "pending", "jobId": job_id}),
            status_code=200,
            mimetype="application/json",
        )

    try:
        entity = json.loads(row)
    except (TypeError, ValueError):
        return func.HttpResponse(
            json.dumps({"status": "pending", "jobId": job_id}),
            status_code=200,
            mimetype="application/json",
        )

    return func.HttpResponse(
        json.dumps(
            {
                "status": entity.get("status", "done"),
                "value": entity.get("value"),
                "jobId": job_id,
            }
        ),
        status_code=200,
        mimetype="application/json",
    )
