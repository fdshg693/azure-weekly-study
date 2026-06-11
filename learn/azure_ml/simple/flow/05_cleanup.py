"""オンラインエンドポイントを削除する (記事 9 章の課金注意)。

Online Endpoint の裏の VM は常時起動 = 常時課金。検証が終わったら必ず削除する。
custom track (03) の .last_endpoint と MLflow track (mlflow_deploy.py) の
.last_endpoint_mlflow の両方を見て、立っているものをまとめて消す。
Workspace ごと消したい場合は justfile の destroy (リソースグループ削除) を使う。
"""

import os

from _client import get_ml_client

# (マーカーファイル, 説明) のリスト。立っているものだけ消す。
MARKERS = [
    (".last_endpoint", "custom track (03)"),
    (".last_endpoint_mlflow", "MLflow track (mlflow_deploy)"),
]


def main() -> None:
    ml = get_ml_client()

    deleted_any = False
    for marker, label in MARKERS:
        if not os.path.exists(marker):
            continue
        with open(marker, encoding="utf-8") as f:
            endpoint_name = f.read().strip()
        if not endpoint_name:
            os.remove(marker)
            continue

        print(f"deleting endpoint (常時課金を止める): {endpoint_name}  [{label}]")
        ml.online_endpoints.begin_delete(name=endpoint_name).result()
        os.remove(marker)
        print(f"deleted: {endpoint_name}")
        deleted_any = True

    if not deleted_any:
        print("削除対象のエンドポイントが無い (.last_endpoint / .last_endpoint_mlflow いずれも無し)。")


if __name__ == "__main__":
    main()
