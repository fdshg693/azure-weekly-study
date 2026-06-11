"""MLClient ファクトリ (記事 3 章)。すべての操作の起点。

認証は DefaultAzureCredential に任せる (az login 済みならそのまま通る)。
接続先は justfile の write-config が Bicep 出力から生成した config.json を読む。
"""

from azure.ai.ml import MLClient
from azure.identity import DefaultAzureCredential


def get_ml_client() -> MLClient:
    # config.json (プロジェクト直下) から subscription / resource group / workspace を読む。
    # MLClient(...) の生成時点ではまだ接続せず、最初の実呼び出しで接続する (遅延初期化)。
    return MLClient.from_config(credential=DefaultAzureCredential(), path="config.json")
