"""Data asset を読んで線形回帰を学習する超最小スクリプト (記事 6・7 章 command job の中身)。

ローカルの `python train.py` をそのまま Azure ML の command job として動かす。
入力データは --data が指す CSV (x,y 列) から読む。クラウドではこのパスに、登録済み
Data asset (azureml:toy-data@latest) がマウントされて渡ってくる (記事 6 章)。
学習済みモデルは --model_output が指すフォルダに model.pkl として保存する。
このフォルダはジョブの「出力」として Workspace に記録され、後でモデル登録に使える。
"""

import argparse
from pathlib import Path

import joblib
import pandas as pd
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error, r2_score


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=str, required=True,
                        help="x,y 列を持つ CSV ファイル (Data asset がマウントされる)")
    parser.add_argument("--model_output", type=str, required=True,
                        help="モデルを書き出すフォルダ (ジョブ出力にマウントされる)")
    args = parser.parse_args()

    # --- データ読み込み: Data asset の CSV を読む (真の関係は y = 3x + 2) ---
    df = pd.read_csv(args.data)
    x = df[["x"]].to_numpy()
    y = df["y"].to_numpy()

    # --- 学習 ---
    model = LinearRegression().fit(x, y)
    pred = model.predict(x)
    mse = float(mean_squared_error(y, pred))
    r2 = float(r2_score(y, pred))

    print(f"学習サンプル数: {len(df)}")
    print(f"推定: y = {model.coef_[0]:.3f} x + {model.intercept_:.3f}  (真値 3x + 2)")
    print(f"MSE = {mse:.4f} / R2 = {r2:.4f}")

    # --- メトリクスを MLflow 経由で Azure ML に記録 (Studio のジョブ画面に出る) ---
    # ジョブ実行時は Azure ML が tracking URI を自動設定する。ローカル単体実行でも
    # 失敗しないよう try で囲む。
    try:
        import mlflow

        mlflow.log_param("n_samples", len(df))
        mlflow.log_metric("mse", mse)
        mlflow.log_metric("r2", r2)
    except Exception as exc:  # noqa: BLE001
        print(f"mlflow ログはスキップ: {exc}")

    # --- モデルを出力フォルダへ保存 ---
    out_dir = Path(args.model_output)
    out_dir.mkdir(parents=True, exist_ok=True)
    model_path = out_dir / "model.pkl"
    joblib.dump(model, model_path)
    print(f"モデルを保存: {model_path}")


if __name__ == "__main__":
    main()
