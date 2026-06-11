"""ローカルの CSV を Data asset として登録する (記事 6 章)。

記事 6 章で触れた Datastore / Data asset を最小形で実体化する。data/toy-data.csv
(x,y 列を持つ合成データ y ≈ 3x + 2) を URI_FILE の Data asset として登録する。

ポイント: path にローカルファイルを渡して create_or_update すると、SDK が既定
Datastore (= Workspace の Storage) へアップロードしてからバージョン付きで参照を
登録する。これで「データ → ジョブ → モデル」の lineage が繋がり、01 の学習ジョブが
azureml:toy-data@latest としてこのデータを入力に取れるようになる。
"""

from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import Data

from _client import get_ml_client

DATA_NAME = "toy-data"


def main() -> None:
    ml = get_ml_client()

    data = Data(
        # ローカルパス。登録時に既定 Datastore へアップロードされ、azureml:// 参照になる。
        path="data/toy-data.csv",
        type=AssetTypes.URI_FILE,
        name=DATA_NAME,
        description="toy linear regression data: columns x,y where y ~= 3x + 2",
    )
    registered = ml.data.create_or_update(data)
    print(f"registered data asset: {registered.name}:{registered.version}")
    print(f"  -> 01 はこれを azureml:{registered.name}@latest として入力に取る")


if __name__ == "__main__":
    main()
