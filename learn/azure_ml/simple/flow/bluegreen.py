"""Blue/Green デプロイとトラフィック分割を体験する (記事 9 章の応用・発展レシピ)。

03 が作った Endpoint (窓口) には、すでに blue という Deployment が 100% で乗っている。
ここに green を追加し、トラフィックを割合で振り分けることで「無停止で新バージョンへ
寄せていく」カナリアリリースを体験する。Endpoint と Deployment を分ける設計の意味
(窓口は固定のまま、裏の VM 群だけ差し替える) がここで効いてくる。

使い方 (03/04 のあと、05 cleanup の前に):
  python bluegreen.py deploy-green   # green を追加し blue:90 / green:10 のカナリア
  python bluegreen.py promote        # green:100 に寄せる (blue へは流さない)
  python bluegreen.py rollback       # blue:100 へ戻し green を削除する

教材上の割り切り: green は新しいモデル版の想定だが、最小形では blue と同じ
model@latest / env@latest / score.py を載せる (差し替えの「仕組み」を見るのが目的)。
実運用では green に新バージョンの Model を載せ、メトリクスを見ながら寄せていく。
"""

import argparse

from azure.ai.ml.entities import (
    CodeConfiguration,
    ManagedOnlineDeployment,
)

from _client import get_ml_client

MODEL_NAME = "toy-linreg-model"
ENV_NAME = "toy-linreg-env"


def read_endpoint_name() -> str:
    with open(".last_endpoint", encoding="utf-8") as f:
        return f.read().strip()


def deploy_green(ml, endpoint_name: str) -> None:
    """green Deployment を作り、blue:90 / green:10 のカナリアにする。"""
    deployment = ManagedOnlineDeployment(
        name="green",
        endpoint_name=endpoint_name,
        model=f"{MODEL_NAME}@latest",
        environment=f"{ENV_NAME}@latest",
        code_configuration=CodeConfiguration(
            code="./onlinescoring", scoring_script="score.py"
        ),
        instance_type="Standard_DS2_v2",
        instance_count=1,
    )
    ml.online_deployments.begin_create_or_update(deployment).result()
    print("deployment 'green' created")

    _set_traffic(ml, endpoint_name, {"blue": 90, "green": 10})
    print("traffic: blue 90% / green 10% (カナリア)")


def promote(ml, endpoint_name: str) -> None:
    """トラフィックを green に 100% 寄せる (blue は残すが流さない)。"""
    _set_traffic(ml, endpoint_name, {"blue": 0, "green": 100})
    print("traffic: green 100% (blue は待機。問題なければ blue を削除してよい)")


def rollback(ml, endpoint_name: str) -> None:
    """blue:100 に戻し、green Deployment を削除する。"""
    _set_traffic(ml, endpoint_name, {"blue": 100})
    print("traffic: blue 100% (ロールバック)")
    ml.online_deployments.begin_delete(
        name="green", endpoint_name=endpoint_name
    ).result()
    print("deployment 'green' deleted")


def _set_traffic(ml, endpoint_name: str, traffic: dict) -> None:
    endpoint = ml.online_endpoints.get(endpoint_name)
    endpoint.traffic = traffic
    ml.online_endpoints.begin_create_or_update(endpoint).result()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action",
        choices=["deploy-green", "promote", "rollback"],
        help="deploy-green: green追加+カナリア / promote: green100% / rollback: blue100%+green削除",
    )
    args = parser.parse_args()

    ml = get_ml_client()
    endpoint_name = read_endpoint_name()
    print(f"endpoint: {endpoint_name}")

    if args.action == "deploy-green":
        deploy_green(ml, endpoint_name)
    elif args.action == "promote":
        promote(ml, endpoint_name)
    elif args.action == "rollback":
        rollback(ml, endpoint_name)


if __name__ == "__main__":
    main()
