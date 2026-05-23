"""学習ジョブの出力を Model として登録する (記事 8 章)。

01 が控えたジョブ名から出力 model_output を参照し、CUSTOM_MODEL として登録する。
登録すると「どの学習ジョブから生まれたモデルか」が追跡できる状態でバージョン管理される。
"""

from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import Model

from _client import get_ml_client

MODEL_NAME = "toy-linreg-model"


def main() -> None:
    ml = get_ml_client()

    with open(".last_job", encoding="utf-8") as f:
        job_name = f.read().strip()

    model = Model(
        # ジョブ出力を指す azureml:// パス。lineage (どのジョブ由来か) が残る。
        path=f"azureml://jobs/{job_name}/outputs/model_output",
        name=MODEL_NAME,
        type=AssetTypes.CUSTOM_MODEL,
        description="toy linear regression model (joblib)",
    )
    registered = ml.models.create_or_update(model)
    print(f"registered model: {registered.name}:{registered.version}")


if __name__ == "__main__":
    main()
