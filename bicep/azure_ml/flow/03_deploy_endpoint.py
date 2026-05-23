"""登録モデルを Managed Online Endpoint にデプロイする (記事 9 章)。

Endpoint (窓口) と Deployment (実体の VM 群) を分けて作り、blue に 100% 流す。
エンドポイント名はリージョン内で一意でないといけないので、毎回ランダムな
サフィックスを付け、04/05 が読めるよう .last_endpoint に控える。

注意: ここで作る VM は常時起動 = 立てている間ずっと課金される。検証が終わったら
必ず 05 (just cleanup) で削除すること。
"""

import uuid

from azure.ai.ml.entities import (
    CodeConfiguration,
    ManagedOnlineDeployment,
    ManagedOnlineEndpoint,
)

from _client import get_ml_client

MODEL_NAME = "toy-linreg-model"
ENV_NAME = "toy-linreg-env"


def main() -> None:
    ml = get_ml_client()

    endpoint_name = f"toy-linreg-{uuid.uuid4().hex[:6]}"

    # --- 1) 窓口 (Endpoint) を作る ---
    endpoint = ManagedOnlineEndpoint(name=endpoint_name, auth_mode="key")
    ml.online_endpoints.begin_create_or_update(endpoint).result()
    print(f"endpoint ready: {endpoint_name}")

    # --- 2) 実体 (Deployment) を作る。学習と同じ Environment を使い回す ---
    deployment = ManagedOnlineDeployment(
        name="blue",
        endpoint_name=endpoint_name,
        model=f"{MODEL_NAME}@latest",
        environment=f"{ENV_NAME}@latest",
        code_configuration=CodeConfiguration(
            code="./onlinescoring", scoring_script="score.py"
        ),
        instance_type="Standard_DS3_v2",
        instance_count=1,
    )
    ml.online_deployments.begin_create_or_update(deployment).result()
    print("deployment 'blue' created")

    # --- 3) トラフィックを blue に 100% 流す ---
    endpoint.traffic = {"blue": 100}
    ml.online_endpoints.begin_create_or_update(endpoint).result()
    print("traffic: blue 100%")

    with open(".last_endpoint", "w", encoding="utf-8") as f:
        f.write(endpoint_name)
    print(f"saved endpoint name to .last_endpoint: {endpoint_name}")


if __name__ == "__main__":
    main()
