"""VM コマンドランナー Function App.

HTTP Trigger:
    POST /api/run  body: { "command": "<alias>" }
        - ホワイトリスト済みのコマンド alias のみ受け付ける
        - VM が deallocated/stopped なら 202 を返し、バックグラウンド起動を試みる
        - VM が running なら Run Command を実行して結果を返す

Timer Trigger (5 分毎):
    - Table Storage の lastAccessUtc を確認し、IDLE_MINUTES_BEFORE_STOP を超えていたら VM を deallocate
"""

from __future__ import annotations

import datetime as dt
import logging
import os
from typing import Any

import azure.functions as func # type: ignore[import]
from azure.core.exceptions import ResourceNotFoundError # type: ignore[import]
from azure.data.tables import TableClient, UpdateMode # type: ignore[import]
from azure.identity import DefaultAzureCredential # type: ignore[import]
from azure.mgmt.compute import ComputeManagementClient # type: ignore[import]
from azure.mgmt.compute.models import RunCommandInput, RunCommandInputParameter # type: ignore[import]

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

# ---------------------------------------------------------------------------
# 環境変数
# ---------------------------------------------------------------------------
SUBSCRIPTION_ID = os.environ["SUBSCRIPTION_ID"]
TARGET_VM_NAME = os.environ["TARGET_VM_NAME"]
TARGET_VM_RG = os.environ["TARGET_VM_RESOURCE_GROUP"]
STORAGE_ACCOUNT = os.environ["STORAGE_ACCOUNT_NAME"]
TABLE_NAME = os.environ.get("STORAGE_TABLE_NAME", "vmstate")
IDLE_MINUTES = int(os.environ.get("IDLE_MINUTES_BEFORE_STOP", "10"))

# State table のキー (固定)
STATE_PARTITION = "vm"
STATE_ROW = TARGET_VM_NAME

# ---------------------------------------------------------------------------
# ホワイトリスト
# ---------------------------------------------------------------------------
# alias → 実行されるシェルコマンド (固定文字列)。引数を受け取らない設計にすることで
# コマンドインジェクションを根本的に防ぐ。
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
# 共有クライアント (コールドスタート時に初期化、warm 間で再利用)
# ---------------------------------------------------------------------------
_credential = DefaultAzureCredential()
_compute = ComputeManagementClient(_credential, SUBSCRIPTION_ID)
_table = TableClient(
    endpoint=f"https://{STORAGE_ACCOUNT}.table.core.windows.net",
    table_name=TABLE_NAME,
    credential=_credential,
)


# ---------------------------------------------------------------------------
# 状態管理ヘルパー
# ---------------------------------------------------------------------------
def _touch_last_access() -> None:
    """lastAccessUtc を現在時刻に更新。"""
    entity = {
        "PartitionKey": STATE_PARTITION,
        "RowKey": STATE_ROW,
        "lastAccessUtc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    _table.upsert_entity(entity=entity, mode=UpdateMode.REPLACE)


def _get_last_access() -> dt.datetime | None:
    try:
        entity = _table.get_entity(partition_key=STATE_PARTITION, row_key=STATE_ROW)
    except ResourceNotFoundError:
        return None
    raw = entity.get("lastAccessUtc")
    if not raw:
        return None
    return dt.datetime.fromisoformat(raw)


def _get_vm_power_state() -> str:
    """'running' / 'stopped' / 'deallocated' / 'starting' / 'unknown' を返す。"""
    iv = _compute.virtual_machines.instance_view(TARGET_VM_RG, TARGET_VM_NAME)
    for s in iv.statuses or []:
        code = (s.code or "").lower()
        if code.startswith("powerstate/"):
            return code.split("/", 1)[1]
    return "unknown"


# ---------------------------------------------------------------------------
# HTTP Trigger: /api/run
# ---------------------------------------------------------------------------
@app.route(route="run", methods=["POST"])
def run_command(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            '{"error":"invalid JSON body"}', status_code=400, mimetype="application/json"
        )

    alias = (body or {}).get("command")
    if not alias or alias not in COMMAND_WHITELIST:
        return func.HttpResponse(
            f'{{"error":"command not allowed","allowed":{list(COMMAND_WHITELIST.keys())}}}',
            status_code=400,
            mimetype="application/json",
        )
    shell_command = COMMAND_WHITELIST[alias]

    # アクセス記録 (起動中/停止中いずれでも更新する：アクティビティ自体を計測したいため)
    _touch_last_access()

    power = _get_vm_power_state()
    logging.info("VM power state: %s", power)

    if power != "running":
        # 停止中/起動中いずれの場合も begin_start を呼ぶ (起動中なら冪等で no-op)。
        # await せず即座に 202 を返してクライアントに再試行を促す。
        try:
            _compute.virtual_machines.begin_start(TARGET_VM_RG, TARGET_VM_NAME)
        except Exception:  # pragma: no cover
            logging.exception("failed to begin_start VM")
            return func.HttpResponse(
                '{"error":"VM is not running and failed to start"}',
                status_code=503,
                mimetype="application/json",
            )
        return func.HttpResponse(
            f'{{"status":"VM_STARTING","power_state":"{power}","message":"VM was not running; start initiated. Retry in ~1-2 minutes."}}',
            status_code=202,
            mimetype="application/json",
        )

    # 実行
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
    except Exception as e:  # pragma: no cover
        logging.exception("run_command failed")
        return func.HttpResponse(
            f'{{"error":"run_command failed","detail":"{type(e).__name__}"}}',
            status_code=500,
            mimetype="application/json",
        )

    # 結果整形
    outputs = []
    for v in result.value or []:
        outputs.append({"code": v.code, "level": v.level, "message": v.message})

    import json

    return func.HttpResponse(
        json.dumps(
            {
                "status": "OK",
                "alias": alias,
                "command": shell_command,
                "outputs": outputs,
            }
        ),
        status_code=200,
        mimetype="application/json",
    )


# ---------------------------------------------------------------------------
# HTTP Trigger: /api/status (デバッグ用)
# ---------------------------------------------------------------------------
@app.route(route="status", methods=["GET"])
def status(req: func.HttpRequest) -> func.HttpResponse:
    import json

    last = _get_last_access()
    payload: dict[str, Any] = {
        "vm_name": TARGET_VM_NAME,
        "power_state": _get_vm_power_state(),
        "last_access_utc": last.isoformat() if last else None,
        "idle_minutes_threshold": IDLE_MINUTES,
        "allowed_commands": list(COMMAND_WHITELIST.keys()),
    }
    return func.HttpResponse(
        json.dumps(payload), status_code=200, mimetype="application/json"
    )


# ---------------------------------------------------------------------------
# Timer Trigger: 5 分毎にアイドル判定
# ---------------------------------------------------------------------------
@app.schedule(schedule="0 */5 * * * *", arg_name="timer", run_on_startup=False, use_monitor=True)
def auto_stop(timer: func.TimerRequest) -> None:
    power = _get_vm_power_state()
    if power != "running":
        logging.info("auto_stop: VM is not running (state=%s); skip", power)
        return

    last = _get_last_access()
    if last is None:
        # 一度もアクセスがない & running はおかしい状態だが、安全側で deallocate
        logging.warning("auto_stop: no lastAccessUtc found; deallocating")
        _compute.virtual_machines.begin_deallocate(TARGET_VM_RG, TARGET_VM_NAME)
        return

    idle = dt.datetime.now(dt.timezone.utc) - last
    logging.info("auto_stop: idle=%s threshold=%d min", idle, IDLE_MINUTES)
    if idle > dt.timedelta(minutes=IDLE_MINUTES):
        logging.info("auto_stop: idle exceeded threshold; deallocating VM")
        _compute.virtual_machines.begin_deallocate(TARGET_VM_RG, TARGET_VM_NAME)
