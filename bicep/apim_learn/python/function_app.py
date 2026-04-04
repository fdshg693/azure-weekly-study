"""
シンプルな CRUD API の Azure Function App

インメモリデータストアを使用した、アイテム管理の REST API です。
Python v2 プログラミングモデル（デコレーターベース）を使用しています。

エンドポイント:
  GET    /api/items        - 全アイテムの一覧取得
  GET    /api/items/{id}   - 指定IDのアイテム取得
  POST   /api/items        - 新規アイテム作成
  PUT    /api/items/{id}   - アイテム更新
  DELETE /api/items/{id}   - アイテム削除
"""

import azure.functions as func  # type: ignore
import json
import logging
import os
import secrets
import uuid

app = func.FunctionApp()

# インメモリデータストア（デモ用）
# 注意: Function App の再起動やスケーリングでデータはリセットされます
items: dict[str, dict] = {}


def require_backend_access(req: func.HttpRequest) -> func.HttpResponse | None:
    """APIM から付与される内部ヘッダーを検証する"""
    expected_secret = os.getenv("BACKEND_SHARED_SECRET")
    if not expected_secret:
        return None

    provided_secret = req.headers.get("x-backend-auth", "")
    if secrets.compare_digest(provided_secret, expected_secret):
        return None

    logging.warning("バックエンド認証に失敗しました")
    return func.HttpResponse(
        json.dumps({"error": "Unauthorized"}),
        mimetype="application/json",
        status_code=401,
    )


# ============================================================================
# 一覧取得 & 新規作成
# ============================================================================


@app.route(route="items", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def list_items(req: func.HttpRequest) -> func.HttpResponse:
    """全アイテムの一覧を取得する"""
    unauthorized = require_backend_access(req)
    if unauthorized:
        return unauthorized

    logging.info("GET /api/items - 一覧取得")
    return func.HttpResponse(
        json.dumps(list(items.values()), ensure_ascii=False),
        mimetype="application/json",
        status_code=200,
    )


@app.route(route="items", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
def create_item(req: func.HttpRequest) -> func.HttpResponse:
    """新規アイテムを作成する"""
    unauthorized = require_backend_access(req)
    if unauthorized:
        return unauthorized

    logging.info("POST /api/items - 新規作成")

    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"error": "リクエストボディが不正です。JSON形式で送信してください。"}),
            mimetype="application/json",
            status_code=400,
        )

    if "name" not in body:
        return func.HttpResponse(
            json.dumps({"error": "'name' フィールドは必須です。"}),
            mimetype="application/json",
            status_code=400,
        )

    item_id = str(uuid.uuid4())
    item = {
        "id": item_id,
        "name": body["name"],
        "description": body.get("description", ""),
    }
    items[item_id] = item

    logging.info(f"アイテム作成: {item_id}")
    return func.HttpResponse(
        json.dumps(item, ensure_ascii=False),
        mimetype="application/json",
        status_code=201,
    )


# ============================================================================
# 個別取得・更新・削除
# ============================================================================


@app.route(route="items/{id}", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def get_item(req: func.HttpRequest) -> func.HttpResponse:
    """指定IDのアイテムを取得する"""
    unauthorized = require_backend_access(req)
    if unauthorized:
        return unauthorized

    item_id = req.route_params.get("id")
    logging.info(f"GET /api/items/{item_id} - 個別取得")

    item = items.get(item_id)
    if not item:
        return func.HttpResponse(
            json.dumps({"error": "アイテムが見つかりません。"}),
            mimetype="application/json",
            status_code=404,
        )

    return func.HttpResponse(
        json.dumps(item, ensure_ascii=False),
        mimetype="application/json",
        status_code=200,
    )


@app.route(route="items/{id}", methods=["PUT"], auth_level=func.AuthLevel.ANONYMOUS)
def update_item(req: func.HttpRequest) -> func.HttpResponse:
    """アイテムを更新する"""
    unauthorized = require_backend_access(req)
    if unauthorized:
        return unauthorized

    item_id = req.route_params.get("id")
    logging.info(f"PUT /api/items/{item_id} - 更新")

    if item_id not in items:
        return func.HttpResponse(
            json.dumps({"error": "アイテムが見つかりません。"}),
            mimetype="application/json",
            status_code=404,
        )

    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"error": "リクエストボディが不正です。JSON形式で送信してください。"}),
            mimetype="application/json",
            status_code=400,
        )

    item = items[item_id]
    if "name" in body:
        item["name"] = body["name"]
    if "description" in body:
        item["description"] = body["description"]

    logging.info(f"アイテム更新: {item_id}")
    return func.HttpResponse(
        json.dumps(item, ensure_ascii=False),
        mimetype="application/json",
        status_code=200,
    )


@app.route(route="items/{id}", methods=["DELETE"], auth_level=func.AuthLevel.ANONYMOUS)
def delete_item(req: func.HttpRequest) -> func.HttpResponse:
    """アイテムを削除する"""
    unauthorized = require_backend_access(req)
    if unauthorized:
        return unauthorized

    item_id = req.route_params.get("id")
    logging.info(f"DELETE /api/items/{item_id} - 削除")

    if item_id not in items:
        return func.HttpResponse(
            json.dumps({"error": "アイテムが見つかりません。"}),
            mimetype="application/json",
            status_code=404,
        )

    deleted_item = items.pop(item_id)
    logging.info(f"アイテム削除: {item_id}")
    return func.HttpResponse(
        json.dumps(deleted_item, ensure_ascii=False),
        mimetype="application/json",
        status_code=200,
    )
