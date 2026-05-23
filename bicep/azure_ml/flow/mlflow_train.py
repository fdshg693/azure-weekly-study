"""MLflow 形式の学習ジョブを投げる (記事 7〜8 章・もう一つの流儀)。

01 + 02 (学習 → 別ステップで登録) に対して、こちらは 1 本で済む:
train_mlflow.py が mlflow.sklearn.log_model(registered_model_name=...) でジョブの中から
直接 Model を登録するため、登録専用ステップ (02 相当) が要らない。

入力データは 01 と同じ Data asset (azureml:toy-data@latest)、Environment も同じものを
使い回す。出力 (model_output) は宣言しない — モデルは MLflow が記録・登録する。
"""

from azure.ai.ml import Input, command
from azure.ai.ml.constants import AssetTypes, InputOutputModes

from _client import get_ml_client

ENV_NAME = "toy-linreg-env"
DATA_NAME = "toy-data"
MLFLOW_MODEL_NAME = "toy-linreg-mlflow"


def main() -> None:
    ml = get_ml_client()

    job = command(
        code="./src",
        command=(
            "python train_mlflow.py --data ${{inputs.data}} "
            f"--registered_model_name {MLFLOW_MODEL_NAME}"
        ),
        inputs={
            "data": Input(
                type=AssetTypes.URI_FILE,
                # 注: "azureml:" は付けない。azure-ai-ml 1.33.0 では "azureml:name@latest" の
                # ラベル解決でプレフィックスが剥がれず container 404 になる (":version" 指定は別経路で無事)。
                # "name@latest" 形式なら SDK バージョンを問わず最新版を解決できる。
                path=f"{DATA_NAME}@latest",
                mode=InputOutputModes.RO_MOUNT,
            )
        },
        environment=f"{ENV_NAME}@latest",
        display_name="toy-linreg-train-mlflow",
        experiment_name="toy-linreg",
    )

    returned = ml.jobs.create_or_update(job)
    print(f"submitted job: {returned.name}")
    print(f"studio: {returned.studio_url}")

    # 完了までストリーム表示。成功すればジョブ内で Model 登録まで終わっている。
    ml.jobs.stream(returned.name)
    print(f"MLFLOW model registered in-job: {MLFLOW_MODEL_NAME}@latest")
    print("  -> 別途の登録ステップ (02 相当) は不要。mlflow_deploy.py でそのままデプロイできる")


if __name__ == "__main__":
    main()
