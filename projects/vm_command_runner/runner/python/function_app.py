"""VM コマンドランナー Function App.

HTTP Trigger:
    POST /api/run      body: { "command": "<alias>" }
    GET  /api/status   現在の電源状態 / 最終アクセス / 許可コマンド
    POST /api/start    VM を起動 (begin_start)
    POST /api/stop     VM を deallocate
    GET  /api/logs     直近の実行履歴 (?limit=50)

認証:
    AuthLevel.ANONYMOUS にしてあるが、Bicep 側で App Service Easy Auth (AAD)
    を有効化し、allowedPrincipals に App Service の MI のみを登録するため、
    実際には未認証アクセスは Function 手前で 401 になる。

Timer Trigger (5 分毎):
    - lastAccessUtc を確認し、IDLE_MINUTES_BEFORE_STOP を超えていたら deallocate
"""

from __future__ import annotations

import datetime as dt
import json
import logging
import os
import uuid
from typing import Any

import azure.functions as func  # type: ignore[import]
from azure.core.exceptions import ResourceNotFoundError  # type: ignore[import]
from azure.data.tables import TableClient, UpdateMode  # type: ignore[import]
from azure.identity import DefaultAzureCredential  # type: ignore[import]
from azure.mgmt.compute import ComputeManagementClient  # type: ignore[import]
from azure.mgmt.compute.models import RunCommandInput  # type: ignore[import]

# Easy Auth が前段で認証する想定なので、Function 自体は ANONYMOUS。
app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# ---------------------------------------------------------------------------
# 環境変数
# ---------------------------------------------------------------------------
SUBSCRIPTION_ID = os.environ["SUBSCRIPTION_ID"]
TARGET_VM_NAME = os.environ["TARGET_VM_NAME"]
TARGET_VM_RG = os.environ["TARGET_VM_RESOURCE_GROUP"]
STORAGE_ACCOUNT = os.environ["STORAGE_ACCOUNT_NAME"]
STATE_TABLE = os.environ.get("STORAGE_TABLE_NAME", "vmstate")
LOG_TABLE = os.environ.get("STORAGE_LOG_TABLE_NAME", "vmlog")
IDLE_MINUTES = int(os.environ.get("IDLE_MINUTES_BEFORE_STOP", "10"))

STATE_PARTITION = "vm"
STATE_ROW = TARGET_VM_NAME

# ---------------------------------------------------------------------------
# ホワイトリスト
# ---------------------------------------------------------------------------
COMMAND_WHITELIST: dict[str, str] = {
    "whoami": "whoami",
    "uptime": "uptime",
    "df": "df -h",
    "free": "free -h",
    "uname": "uname -a",
    "date": "date -u",
    "hostname": "hostname",
    "os-release": "cat /etc/os-release",
}

# ---------------------------------------------------------------------------
# 共有クライアント
# ---------------------------------------------------------------------------
_credential = DefaultAzureCredential()
_compute = ComputeManagementClient(_credential, SUBSCRIPTION_ID)
_state_table = TableClient(
    endpoint=f"https://{STORAGE_ACCOUNT}.table.core.windows.net",
    table_name=STATE_TABLE,
    credential=_credential,
)
_log_table = TableClient(
    endpoint=f"https://{STORAGE_ACCOUNT}.table.core.windows.net",
    table_name=LOG_TABLE,
    credential=_credential,
)


# ---------------------------------------------------------------------------
# ヘルパー
# ---------------------------------------------------------------------------
def _json(payload: Any, status: int = 200) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(payload, ensure_ascii=False),
        status_code=status,
        mimetype="application/json",
    )


def _caller_principal(req: func.HttpRequest) -> str | None:
    """Easy Auth が渡す呼び出し元 principal id (object id) を取得。"""
    return req.headers.get("x-ms-client-principal-id")


def _touch_last_access() -> None:
    entity = {
        "PartitionKey": STATE_PARTITION,
        "RowKey": STATE_ROW,
        "lastAccessUtc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    _state_table.upsert_entity(entity=entity, mode=UpdateMode.REPLACE)


def _get_last_access() -> dt.datetime | None:
    try:
        entity = _state_table.get_entity(partition_key=STATE_PARTITION, row_key=STATE_ROW)
    except ResourceNotFoundError:
        return None
    raw = entity.get("lastAccessUtc")
    if not raw:
        return None
    return dt.datetime.fromisoformat(raw)


def _get_vm_power_state() -> str:
    iv = _compute.virtual_machines.instance_view(TARGET_VM_RG, TARGET_VM_NAME)
    for s in iv.statuses or []:
        code = (s.code or "").lower()
        if code.startswith("powerstate/"):
            return code.split("/", 1)[1]
    return "unknown"


def _append_log(alias: str, status: str, caller: str | None, detail: dict[str, Any]) -> None:
    """実行履歴を vmlog テーブルに追記。

    RowKey は (max_ts - now_ts) を 19 桁にゼロ詰めしたものを使い、自然順で新しい順に並ぶ。
    """
    now = dt.datetime.now(dt.timezone.utc)
    max_ts = 9_999_999_999_999  # 13 桁余裕を持たせる
    row_key = f"{max_ts - int(now.timestamp() * 1000):019d}_{uuid.uuid4().hex[:8]}"
    entity = {
        "PartitionKey": TARGET_VM_NAME,
        "RowKey": row_key,
        "timestampUtc": now.isoformat(),
        "alias": alias,
        "status": status,
        "caller": caller or "",
        "detail": json.dumps(detail, ensure_ascii=False)[:30_000],
    }
    try:
        _log_table.upsert_entity(entity=entity, mode=UpdateMode.REPLACE)
    except Exception:  # ログ書き込み失敗は本処理を止めない
        logging.exception("failed to write log entry")


# ---------------------------------------------------------------------------
# HTTP: /api/run
# ---------------------------------------------------------------------------
@app.route(route="run", methods=["POST"])
def run_command(req: func.HttpRequest) -> func.HttpResponse:
    caller = _caller_principal(req)
    try:
        body = req.get_json()
    except ValueError:
        return _json({"error": "invalid JSON body"}, 400)

    alias = (body or {}).get("command")
    if not alias or alias not in COMMAND_WHITELIST:
        return _json(
            {"error": "command not allowed", "allowed": list(COMMAND_WHITELIST.keys())},
            400,
        )
    shell_command = COMMAND_WHITELIST[alias]

    _touch_last_access()
    power = _get_vm_power_state()
    logging.info("VM power state: %s", power)

    if power != "running":
        try:
            _compute.virtual_machines.begin_start(TARGET_VM_RG, TARGET_VM_NAME)
        except Exception:
            logging.exception("failed to begin_start VM")
            _append_log(alias, "START_FAILED", caller, {"power_state": power})
            return _json({"error": "VM is not running and failed to start"}, 503)
        _append_log(alias, "VM_STARTING", caller, {"power_state": power})
        return _json(
            {
                "status": "VM_STARTING",
                "power_state": power,
                "message": "VM was not running; start initiated. Retry in ~1-2 minutes.",
            },
            202,
        )

    try:
        poller = _compute.virtual_machines.begin_run_command(
            resource_group_name=TARGET_VM_RG,
            vm_name=TARGET_VM_NAME,
            parameters=RunCommandInput(
                command_id="RunShellScript",
                script=[shell_command],
                parameters=[],
            ),
        )
        result = poller.result(timeout=120)
    except Exception as e:
        logging.exception("run_command failed")
        _append_log(alias, "ERROR", caller, {"error_type": type(e).__name__})
        return _json({"error": "run_command failed", "detail": type(e).__name__}, 500)

    outputs = [
        {"code": v.code, "level": v.level, "message": v.message}
        for v in (result.value or [])
    ]
    payload = {"status": "OK", "alias": alias, "command": shell_command, "outputs": outputs}
    _append_log(alias, "OK", caller, {"outputs": outputs})
    return _json(payload, 200)


# ---------------------------------------------------------------------------
# HTTP: /api/status
# ---------------------------------------------------------------------------
@app.route(route="status", methods=["GET"])
def status(req: func.HttpRequest) -> func.HttpResponse:
    last = _get_last_access()
    return _json(
        {
            "vm_name": TARGET_VM_NAME,
            "power_state": _get_vm_power_state(),
            "last_access_utc": last.isoformat() if last else None,
            "idle_minutes_threshold": IDLE_MINUTES,
            "allowed_commands": list(COMMAND_WHITELIST.keys()),
        },
        200,
    )


# ---------------------------------------------------------------------------
# HTTP: /api/start
# ---------------------------------------------------------------------------
@app.route(route="start", methods=["POST"])
def start_vm(req: func.HttpRequest) -> func.HttpResponse:
    caller = _caller_principal(req)
    power = _get_vm_power_state()
    if power == "running":
        return _json({"status": "ALREADY_RUNNING", "power_state": power}, 200)
    try:
        _compute.virtual_machines.begin_start(TARGET_VM_RG, TARGET_VM_NAME)
    except Exception as e:
        logging.exception("begin_start failed")
        _append_log("_start", "ERROR", caller, {"error_type": type(e).__name__})
        return _json({"error": "begin_start failed", "detail": type(e).__name__}, 500)
    _append_log("_start", "STARTING", caller, {"previous_power_state": power})
    return _json({"status": "STARTING", "power_state": power}, 202)


# ---------------------------------------------------------------------------
# HTTP: /api/stop
# ---------------------------------------------------------------------------
@app.route(route="stop", methods=["POST"])
def stop_vm(req: func.HttpRequest) -> func.HttpResponse:
    caller = _caller_principal(req)
    power = _get_vm_power_state()
    if power in ("deallocated", "deallocating", "stopped"):
        return _json({"status": "ALREADY_STOPPED", "power_state": power}, 200)
    try:
        _compute.virtual_machines.begin_deallocate(TARGET_VM_RG, TARGET_VM_NAME)
    except Exception as e:
        logging.exception("begin_deallocate failed")
        _append_log("_stop", "ERROR", caller, {"error_type": type(e).__name__})
        return _json({"error": "begin_deallocate failed", "detail": type(e).__name__}, 500)
    _append_log("_stop", "DEALLOCATING", caller, {"previous_power_state": power})
    return _json({"status": "DEALLOCATING", "power_state": power}, 202)


# ---------------------------------------------------------------------------
# HTTP: /api/logs
# ---------------------------------------------------------------------------
@app.route(route="logs", methods=["GET"])
def list_logs(req: func.HttpRequest) -> func.HttpResponse:
    try:
        limit = int(req.params.get("limit", "50"))
    except ValueError:
        limit = 50
    limit = max(1, min(limit, 200))

    items: list[dict[str, Any]] = []
    try:
        # PartitionKey でフィルタ。RowKey が新しい順に並ぶ設計なので先頭から limit 件取れば OK。
        entities = _log_table.query_entities(
            query_filter=f"PartitionKey eq '{TARGET_VM_NAME}'",
            results_per_page=limit,
        )
        for entity in entities:
            detail_raw = entity.get("detail") or "{}"
            try:
                detail = json.loads(detail_raw)
            except json.JSONDecodeError:
                detail = {"raw": detail_raw}
            items.append(
                {
                    "timestamp_utc": entity.get("timestampUtc"),
                    "alias": entity.get("alias"),
                    "status": entity.get("status"),
                    "caller": entity.get("caller"),
                    "detail": detail,
                }
            )
            if len(items) >= limit:
                break
    except ResourceNotFoundError:
        pass
    return _json({"items": items, "count": len(items)}, 200)


# ---------------------------------------------------------------------------
# Timer: 5 分毎にアイドル判定
# ---------------------------------------------------------------------------
@app.schedule(schedule="0 */5 * * * *", arg_name="timer", run_on_startup=False, use_monitor=True)
def auto_stop(timer: func.TimerRequest) -> None:
    power = _get_vm_power_state()
    if power != "running":
        logging.info("auto_stop: VM is not running (state=%s); skip", power)
        return

    last = _get_last_access()
    if last is None:
        logging.warning("auto_stop: no lastAccessUtc found; deallocating")
        _compute.virtual_machines.begin_deallocate(TARGET_VM_RG, TARGET_VM_NAME)
        _append_log("_auto_stop", "DEALLOCATING", None, {"reason": "no_last_access"})
        return

    idle = dt.datetime.now(dt.timezone.utc) - last
    logging.info("auto_stop: idle=%s threshold=%d min", idle, IDLE_MINUTES)
    if idle > dt.timedelta(minutes=IDLE_MINUTES):
        logging.info("auto_stop: idle exceeded threshold; deallocating VM")
        _compute.virtual_machines.begin_deallocate(TARGET_VM_RG, TARGET_VM_NAME)
        _append_log("_auto_stop", "DEALLOCATING", None, {"idle_minutes": int(idle.total_seconds() // 60)})
