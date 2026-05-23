"""オンラインエンドポイントを削除する (記事 9 章の課金注意)。

Online Endpoint の裏の VM は常時起動 = 常時課金。検証が終わったら必ず削除する。
Workspace ごと消したい場合は justfile の destroy (リソースグループ削除) を使う。
"""

import os

from _client import get_ml_client


def main() -> None:
    ml = get_ml_client()

    if not os.path.exists(".last_endpoint"):
        print(".last_endpoint が無い。削除対象のエンドポイントが分からないので終了。")
        return

    with open(".last_endpoint", encoding="utf-8") as f:
        endpoint_name = f.read().strip()

    print(f"deleting endpoint (常時課金を止める): {endpoint_name}")
    ml.online_endpoints.begin_delete(name=endpoint_name).result()
    os.remove(".last_endpoint")
    print("deleted.")


if __name__ == "__main__":
    main()
