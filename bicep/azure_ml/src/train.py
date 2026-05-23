"""トイデータで線形回帰を学習する超最小スクリプト (記事 7 章 command job の中身)。

ローカルの `python train.py` をそのまま Azure ML の command job として動かす。
データは外部に用意せず、その場で y = 3x + 2 + ノイズ の合成データを作る。
学習済みモデルは --model_output が指すフォルダに model.pkl として保存する。
このフォルダはジョブの「出力」として Workspace に記録され、後でモデル登録に使える。
"""

import argparse
from pathlib import Path

import joblib
import numpy as np
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error, r2_score


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--n_samples", type=int, default=200)
    parser.add_argument("--noise", type=float, default=1.0)
    parser.add_argument("--model_output", type=str, required=True,
                        help="モデルを書き出すフォルダ (ジョブ出力にマウントされる)")
    args = parser.parse_args()

    # --- トイデータ生成: 真の関係は y = 3x + 2 ---
    rng = np.random.default_rng(42)
    x = rng.uniform(-5.0, 5.0, size=(args.n_samples, 1))
    y = 3.0 * x[:, 0] + 2.0 + rng.normal(0.0, args.noise, size=args.n_samples)

    # --- 学習 ---
    model = LinearRegression().fit(x, y)
    pred = model.predict(x)
    mse = float(mean_squared_error(y, pred))
    r2 = float(r2_score(y, pred))

    print(f"学習サンプル数: {args.n_samples}")
    print(f"推定: y = {model.coef_[0]:.3f} x + {model.intercept_:.3f}  (真値 3x + 2)")
    print(f"MSE = {mse:.4f} / R2 = {r2:.4f}")

    # --- メトリクスを MLflow 経由で Azure ML に記録 (Studio のジョブ画面に出る) ---
    # ジョブ実行時は Azure ML が tracking URI を自動設定する。ローカル単体実行でも
    # 失敗しないよう try で囲む。
    try:
        import mlflow

        mlflow.log_param("n_samples", args.n_samples)
        mlflow.log_param("noise", args.noise)
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
