"""作成したリソースを削除する (課金停止)。

deployment → project → account の依存順で明示的に落とす。アカウントを消せば配下も
まとめて消えるが、順番を踏むことで「何がぶら下がっているか」を意識できる。
リソースグループごと一掃するなら just destroy の方が速い。
"""

from azure.identity import DefaultAzureCredential
from azure.mgmt.cognitiveservices import CognitiveServicesManagementClient

from _config import load_config

API_VERSION = "2025-04-01-preview"


def main() -> None:
    cfg = load_config()
    client = CognitiveServicesManagementClient(
        credential=DefaultAzureCredential(),
        subscription_id=cfg["subscription_id"],
        api_version=API_VERSION,
    )
    rg, acc = cfg["resource_group"], cfg["account_name"]

    print(f"deployment '{cfg['model_name']}' を削除中 ...")
    client.deployments.begin_delete(rg, acc, cfg["model_name"]).result()

    print(f"project '{cfg['project_name']}' を削除中 ...")
    client.projects.begin_delete(rg, acc, cfg["project_name"]).result()

    print(f"account '{acc}' を削除中 ...")
    client.accounts.begin_delete(rg, acc).result()
    print("done. (RG ごと消すなら just destroy)")


if __name__ == "__main__":
    main()
