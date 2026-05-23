"""scoring script (記事 9 章)。オンラインエンドポイントのコンテナ内で動く。

init() でモデルを 1 回ロードし、run() でリクエストごとに推論する。
FastAPI でいう起動処理 + エンドポイント関数に当たる役割分担。
"""

import glob
import json
import os

import joblib
import numpy as np

model = None


def init() -> None:
    """コンテナ起動時に 1 回だけ呼ばれる。モデルをメモリにロードする。"""
    global model
    # 登録したモデルは AZUREML_MODEL_DIR 配下に展開される。フォルダ構造に依存しない
    # よう model.pkl を再帰検索する (CUSTOM_MODEL をフォルダ登録した場合に堅牢)。
    model_dir = os.getenv("AZUREML_MODEL_DIR", ".")
    matches = glob.glob(os.path.join(model_dir, "**", "model.pkl"), recursive=True)
    if not matches:
        raise FileNotFoundError(f"model.pkl が {model_dir} 配下に見つからない")
    model = joblib.load(matches[0])
    print(f"loaded model: {matches[0]}")


def run(raw_data: str):
    """リクエストごとに呼ばれる。{"data": [[x], ...]} を受けて予測を返す。"""
    payload = json.loads(raw_data)
    features = np.array(payload["data"], dtype=float)
    preds = model.predict(features)
    return preds.tolist()
