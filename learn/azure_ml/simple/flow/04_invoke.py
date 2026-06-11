"""デプロイ済みエンドポイントに推論リクエストを投げる (記事 9 章の動作確認)。

sample-request.json の x に対し、y = 3x + 2 に近い値が返れば成功。
"""

from _client import get_ml_client


def main() -> None:
    ml = get_ml_client()

    with open(".last_endpoint", encoding="utf-8") as f:
        endpoint_name = f.read().strip()

    response = ml.online_endpoints.invoke(
        endpoint_name=endpoint_name,
        request_file="sample-request.json",
    )
    print(f"endpoint: {endpoint_name}")
    print(f"response: {response}")
    print("(入力 x=[0,1,2,10] に対し おおよそ [2, 5, 8, 32] が返れば成功)")


if __name__ == "__main__":
    main()
