"""MLFLOW ノーコードエンドポイントに推論リクエストを投げる (記事 9 章の動作確認)。

04 (custom track) との違いはリクエスト形式だけ。custom の score.py は {"data": [[x],...]}
を受ける自作仕様だったが、MLFLOW ノーコードデプロイの自動 scoring は MLflow 標準の
{"input_data": {"columns": [...], "data": [[...]]}} を受ける (sample-request-mlflow.json)。
返る予測値は同じ (y ~= 3x + 2) になるはず。
"""

from _client import get_ml_client


def main() -> None:
    ml = get_ml_client()

    with open(".last_endpoint_mlflow", encoding="utf-8") as f:
        endpoint_name = f.read().strip()

    response = ml.online_endpoints.invoke(
        endpoint_name=endpoint_name,
        request_file="sample-request-mlflow.json",
    )
    print(f"endpoint: {endpoint_name}")
    print(f"response: {response}")
    print("(入力 x=[0,1,2,10] に対し おおよそ [2, 5, 8, 32] が返れば成功)")


if __name__ == "__main__":
    main()
