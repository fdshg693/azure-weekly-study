"""Environment を用意して、学習ジョブを Serverless で投げる (記事 5 章 + 7 章)。

compute を指定しない = Serverless。最初の 1 本は Compute を作らずに試せる。
ジョブの出力 model_output を URI_FOLDER として宣言し、train.py がそこに model.pkl
を書く。完了後、その出力を 02 でモデルとして登録する。
"""

from azure.ai.ml import Output, command
from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import Environment

from _client import get_ml_client

ENV_NAME = "toy-linreg-env"


def main() -> None:
    ml = get_ml_client()

    # --- Environment 作成/更新 (記事 5 章)。初回はここから Docker イメージがビルドされる ---
    env = Environment(
        name=ENV_NAME,
        image="mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu22.04:latest",
        conda_file="src/conda.yml",
        description="toy linear regression: sklearn + inference server",
    )
    env = ml.environments.create_or_update(env)
    print(f"environment: {env.name}:{env.version}")

    # --- command job (記事 7 章)。compute 未指定なので Serverless で走る ---
    job = command(
        code="./src",  # このフォルダ一式が Compute 上にアップロードされる
        command=(
            "python train.py --n_samples 200 --noise 1.0 "
            "--model_output ${{outputs.model_output}}"
        ),
        environment=f"{env.name}:{env.version}",
        outputs={"model_output": Output(type=AssetTypes.URI_FOLDER)},
        display_name="toy-linreg-train",
        experiment_name="toy-linreg",
    )

    returned = ml.jobs.create_or_update(job)
    print(f"submitted job: {returned.name}")
    print(f"studio: {returned.studio_url}")

    # 完了までログをストリーム表示 (失敗すれば例外で止まる)
    ml.jobs.stream(returned.name)

    # 02 がこのジョブ出力を参照できるよう、ジョブ名を控える
    with open(".last_job", "w", encoding="utf-8") as f:
        f.write(returned.name)
    print(f"saved job name to .last_job: {returned.name}")


if __name__ == "__main__":
    main()
