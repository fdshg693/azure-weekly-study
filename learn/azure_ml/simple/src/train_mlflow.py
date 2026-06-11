"""MLflow 形式でモデルを学習・登録する (記事 8 章「mlflow でそのまま登録」の流儀)。

train.py (custom model + 自作 score.py) と対になるもう一つの流儀。
やっていることは train.py と同じ「CSV を読んで線形回帰を 1 本」だが、保存方法が違う:

  - train.py        : joblib で model.pkl を吐く → 02 で CUSTOM_MODEL 登録 → score.py が必須
  - train_mlflow.py : mlflow.sklearn.log_model で MLFLOW 形式で記録・登録 → score.py 不要

mlflow.sklearn.log_model に registered_model_name を渡すと、学習ジョブの中でそのまま
Workspace の Model レジストリに登録される (記事 8 章後半)。MLFLOW 形式のモデルは
依存環境とシグネチャ (入力スキーマ) を内包するので、デプロイ時に Environment も
scoring script も書かずに済む = ノーコードデプロイ (mlflow_deploy.py 参照)。
"""

import argparse

import mlflow
import mlflow.sklearn  # mlflow.sklearn.log_model を使うため明示的にロードする
import pandas as pd
from mlflow.models import infer_signature
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error, r2_score


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=str, required=True,
                        help="x,y 列を持つ CSV ファイル (Data asset がマウントされる)")
    parser.add_argument("--registered_model_name", type=str, default="toy-linreg-mlflow",
                        help="この名前で Workspace の Model レジストリに登録する")
    args = parser.parse_args()

    # --- データ読み込み: DataFrame のまま学習し、列名 (x) をシグネチャに残す ---
    df = pd.read_csv(args.data)
    x = df[["x"]]
    y = df["y"]

    # --- 学習 ---
    model = LinearRegression().fit(x, y)
    pred = model.predict(x)
    mse = float(mean_squared_error(y, pred))
    r2 = float(r2_score(y, pred))

    print(f"学習サンプル数: {len(df)}")
    print(f"推定: y = {model.coef_[0]:.3f} x + {model.intercept_:.3f}  (真値 3x + 2)")
    print(f"MSE = {mse:.4f} / R2 = {r2:.4f}")

    mlflow.log_metric("mse", mse)
    mlflow.log_metric("r2", r2)

    # --- MLFLOW 形式で記録 + そのまま登録 ---
    # signature (入力スキーマ) を埋め込むことで、デプロイ時の自動 scoring が型を把握できる。
    mlflow.sklearn.log_model(
        sk_model=model,
        artifact_path="model",
        registered_model_name=args.registered_model_name,
        signature=infer_signature(x, pred),
        input_example=x.head(),
    )
    print(f"registered MLFLOW model: {args.registered_model_name}")


if __name__ == "__main__":
    main()
