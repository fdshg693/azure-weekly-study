"""MLFLOW モデルをノーコードでデプロイする (記事 9 章・もう一つの流儀)。

03 (custom model) との対比がこのファイルの主役。03 では
  - environment=... (学習と同じ環境を明示)
  - code_configuration=CodeConfiguration(code=..., scoring_script="score.py")
を渡していた。MLFLOW 形式のモデルは依存環境と入出力シグネチャを内包しているので、
ここでは environment も score.py も渡さない。Azure ML が MLmodel から推論環境と
scoring を自動生成する = ノーコードデプロイ。

エンドポイント名は 03 と衝突しないよう別サフィックスにし、custom track の .last_endpoint
とは別に .last_endpoint_mlflow に控える (両方を立てて挙動を比べられる)。

注意: 03 と同じく裏の VM は常時課金。確認後は cleanup で必ず削除すること。
"""

import uuid

from azure.ai.ml.entities import (
    ManagedOnlineDeployment,
    ManagedOnlineEndpoint,
)

from _client import get_ml_client

MLFLOW_MODEL_NAME = "toy-linreg-mlflow"


def main() -> None:
    ml = get_ml_client()

    endpoint_name = f"toy-mlflow-{uuid.uuid4().hex[:6]}"

    # --- 1) 窓口 (Endpoint) を作る ---
    endpoint = ManagedOnlineEndpoint(name=endpoint_name, auth_mode="key")
    ml.online_endpoints.begin_create_or_update(endpoint).result()
    print(f"endpoint ready: {endpoint_name}")

    # --- 2) 実体 (Deployment)。environment も code_configuration も無し = ノーコード ---
    deployment = ManagedOnlineDeployment(
        name="blue",
        endpoint_name=endpoint_name,
        model=f"{MLFLOW_MODEL_NAME}@latest",  # MLFLOW 形式なのでこれだけで足りる
        instance_type="Standard_DS2_v2",
        instance_count=1,
    )
    ml.online_deployments.begin_create_or_update(deployment).result()
    print("deployment 'blue' created (no scoring script / no explicit environment)")

    # --- 3) トラフィックを blue に 100% 流す ---
    endpoint.traffic = {"blue": 100}
    ml.online_endpoints.begin_create_or_update(endpoint).result()
    print("traffic: blue 100%")

    with open(".last_endpoint_mlflow", "w", encoding="utf-8") as f:
        f.write(endpoint_name)
    print(f"saved endpoint name to .last_endpoint_mlflow: {endpoint_name}")


if __name__ == "__main__":
    main()
