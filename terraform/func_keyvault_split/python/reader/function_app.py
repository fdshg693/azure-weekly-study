import logging
import os

import azure.functions as func  # type: ignore

app = func.FunctionApp()


# ============================================================================
# Reader: Key Vault reference 経由でシークレットを参照し、メッセージを返す
# ============================================================================
# - auth_level=ANONYMOUS: 関数キー不要、誰でも GET 可能
# - GREETING_NAME は Terraform で次のように設定済み:
#       @Microsoft.KeyVault(SecretUri=https://<vault>.vault.azure.net/secrets/greeting-name)
#   Functions ランタイムが Managed Identity を使って Key Vault から最新値を取得し、
#   この関数からは「ただの環境変数」として見える。
# - 関数コード自体は Key Vault の SDK を一切 import していない（=「読み取り専用 + 最小権限」を表現）。
@app.route(route="message", auth_level=func.AuthLevel.ANONYMOUS, methods=["GET"])
def message(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("reader: building message from KV-injected secret")

    name = os.environ.get("GREETING_NAME", "")

    # Key Vault reference が未解決の場合、Functions は app_settings の値として
    # 「参照式そのままの文字列（@Microsoft.KeyVault(...)）」を渡してくる。
    # 起こり得るタイミング:
    #   - 初回デプロイ直後（RBAC ロール反映前）
    #   - Function App 再起動直後（解決キャッシュが空）
    if not name or name.startswith("@Microsoft.KeyVault"):
        return func.HttpResponse(
            "secret not resolved yet — wait a minute and restart the function app",
            status_code=503,
            mimetype="text/plain",
        )

    return func.HttpResponse(
        f"Hello, {name}! (read-only function — secret loaded via Key Vault reference)",
        status_code=200,
        mimetype="text/plain",
    )
