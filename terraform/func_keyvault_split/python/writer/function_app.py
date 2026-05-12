import json
import logging
import os

import azure.functions as func  # type: ignore
from azure.identity import DefaultAzureCredential # type: ignore
from azure.keyvault.secrets import SecretClient # type: ignore

app = func.FunctionApp()


# ============================================================================
# Writer: Function キー保護 + SDK 経由で Key Vault のシークレット値を更新
# ============================================================================
# - auth_level=FUNCTION: 呼び出しに ?code=<function-key> が必須
# - System-Assigned Managed Identity 経由で Key Vault に「Set Secret」する
#   （= 同名シークレットの新バージョンを作成 = 値の更新）
# - DefaultAzureCredential は Azure 上では MI を、ローカルでは az login の資格情報を
#   自動で拾ってくれるので、同じコードでローカル動作確認もできる
@app.route(route="secret", auth_level=func.AuthLevel.FUNCTION, methods=["POST"])
def update_secret(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("writer: secret update requested")

    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"error": "request body must be JSON"}),
            status_code=400,
            mimetype="application/json",
        )

    new_value = body.get("value") if isinstance(body, dict) else None
    if not isinstance(new_value, str) or not new_value:
        return func.HttpResponse(
            json.dumps({"error": "'value' (non-empty string) is required"}),
            status_code=400,
            mimetype="application/json",
        )

    vault_url = os.environ.get("KEY_VAULT_URL")
    secret_name = os.environ.get("SECRET_NAME")
    if not vault_url or not secret_name:
        return func.HttpResponse(
            json.dumps({"error": "KEY_VAULT_URL or SECRET_NAME not configured"}),
            status_code=500,
            mimetype="application/json",
        )

    credential = DefaultAzureCredential()
    client = SecretClient(vault_url=vault_url, credential=credential)

    secret = client.set_secret(secret_name, new_value)
    logging.info(
        "writer: updated secret name=%s new_version=%s",
        secret.name,
        secret.properties.version,
    )

    return func.HttpResponse(
        json.dumps(
            {
                "status": "ok",
                "name": secret.name,
                "version": secret.properties.version,
            }
        ),
        status_code=200,
        mimetype="application/json",
    )
