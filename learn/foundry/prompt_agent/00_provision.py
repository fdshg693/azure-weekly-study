"""Foundry のリソース一式を Python 管理 SDK だけで作る (コントロールプレーン)。

azure_ml では Bicep が担っていた「基盤づくり」を、ここでは azure-mgmt-cognitiveservices
(CognitiveServicesManagementClient) で行う。Bicep を使わず Python に寄せるのが本プロジェクトの
狙い (azure_sdk/README.md の方針)。作るのは次の 3 つ:

  1. Foundry リソース  = Cognitive Services アカウント (kind=AIServices)
       - allowProjectManagement=True … 「プロジェクトを内包できる」アカウントにする鍵
       - customSubDomainName        … データプレーンのホスト名になる (※グローバルに一意)
  2. プロジェクト       = アカウント配下の子リソース。エージェントはこの中に住む
  3. モデルデプロイ     = カタログのモデル (既定 gpt-4.1-mini) をアカウントに配備
       - デプロイ名をエージェント定義の model に渡す (01 が参照)

最後に 01/02/99 が使う接続情報を config.json に書き出す。

前提:
  - az login 済み
  - アカウント作成には Owner 相当 (Foundry Account Owner 等) が要る

設定は .env (このフォルダ直下) か環境変数で上書きできる (_config が .env を読み込む)。
ACCOUNT (= サブドメイン名) はグローバル一意なので、既定値が取られていたら別名を指定すること。
サブスクリプションは AZURE_SUBSCRIPTION_ID → .env → az の既定サブスクリプション の順で解決する。
"""

import os
import shutil
import subprocess

from azure.identity import DefaultAzureCredential
from azure.mgmt.cognitiveservices import CognitiveServicesManagementClient

from _config import save_config  # import 時に .env を読み込む


def _resolve_subscription() -> str:
    """AZURE_SUBSCRIPTION_ID (env/.env) を優先し、無ければ az の既定サブスクリプションを使う。"""
    sub = os.environ.get("AZURE_SUBSCRIPTION_ID")
    if sub:
        return sub
    az = shutil.which("az")
    if not az:
        raise SystemExit(
            "AZURE_SUBSCRIPTION_ID が未設定で az も見つからない。"
            ".env に書くか、az login してから実行する。"
        )
    out = subprocess.run(
        [az, "account", "show", "--query", "id", "-o", "tsv"],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        raise SystemExit(f"az account show に失敗: {out.stderr.strip()}")
    return out.stdout.strip()


# --- 設定 (.env または環境変数で上書き可) ---
SUBSCRIPTION_ID = _resolve_subscription()
RESOURCE_GROUP = os.environ.get("RG", "rg-foundry-agent")
ACCOUNT_NAME = os.environ.get("ACCOUNT", "foundry-agent-demo")  # ★グローバル一意
PROJECT_NAME = os.environ.get("PROJECT", "agent-project")
LOCATION = os.environ.get("LOCATION", "eastus2")
MODEL_NAME = os.environ.get("MODEL", "gpt-4.1-mini")
MODEL_VERSION = os.environ.get("MODEL_VERSION", "")  # 空なら Azure の既定バージョン
AGENT_NAME = os.environ.get("AGENT", "MyAgent")

# projects / 新しいデプロイ操作を扱うには新しめの API 版が要る (Foundry "new")
API_VERSION = "2025-04-01-preview"


def main() -> None:
    client = CognitiveServicesManagementClient(
        credential=DefaultAzureCredential(),
        subscription_id=SUBSCRIPTION_ID,
        api_version=API_VERSION,
    )

    # --- 1) Foundry アカウント (kind=AIServices) ---
    print(f"[1/3] account '{ACCOUNT_NAME}' を作成/更新中 ...")
    account = client.accounts.begin_create(
        resource_group_name=RESOURCE_GROUP,
        account_name=ACCOUNT_NAME,
        account={
            "location": LOCATION,
            "kind": "AIServices",
            "sku": {"name": "S0"},
            "identity": {"type": "SystemAssigned"},
            "properties": {
                "allowProjectManagement": True,      # ← プロジェクトを内包可能にする
                "customSubDomainName": ACCOUNT_NAME,  # ← データプレーンのホスト名
            },
        },
    ).result()
    # 実際のエンドポイントを確認用に出す (下で組み立てる値とズレていないか照合できる)
    print(f"      done. endpoints={getattr(account.properties, 'endpoints', None)}")

    # --- 2) プロジェクト (アカウント配下) ---
    print(f"[2/3] project '{PROJECT_NAME}' を作成/更新中 ...")
    client.projects.begin_create(
        resource_group_name=RESOURCE_GROUP,
        account_name=ACCOUNT_NAME,
        project_name=PROJECT_NAME,
        project={
            "location": LOCATION,
            "identity": {"type": "SystemAssigned"},
            "properties": {},
        },
    ).result()
    print("      done.")

    # --- 3) モデルデプロイ (アカウント直下。プロジェクト横断で共有される) ---
    print(f"[3/3] deployment '{MODEL_NAME}' を作成/更新中 ...")
    model = {"format": "OpenAI", "name": MODEL_NAME}
    if MODEL_VERSION:
        model["version"] = MODEL_VERSION
    client.deployments.begin_create_or_update(
        resource_group_name=RESOURCE_GROUP,
        account_name=ACCOUNT_NAME,
        deployment_name=MODEL_NAME,  # デプロイ名 = モデル名。01 の model 指定と一致させる
        deployment={
            "properties": {"model": model},
            "sku": {"name": "GlobalStandard", "capacity": 1},
        },
    ).result()
    print("      done.")

    # --- 接続情報を config.json に保存 ---
    # Foundry (new) のプロジェクトエンドポイントの形:
    #   https://<customSubDomain>.services.ai.azure.com/api/projects/<project>
    project_endpoint = (
        f"https://{ACCOUNT_NAME}.services.ai.azure.com/api/projects/{PROJECT_NAME}"
    )
    save_config(
        {
            "subscription_id": SUBSCRIPTION_ID,
            "resource_group": RESOURCE_GROUP,
            "account_name": ACCOUNT_NAME,
            "project_name": PROJECT_NAME,
            "location": LOCATION,
            "model_name": MODEL_NAME,
            "agent_name": AGENT_NAME,
            "project_endpoint": project_endpoint,
        }
    )
    print(f"\nproject_endpoint = {project_endpoint}")
    print(
        "※ Foundry ポータルの welcome 画面に出るエンドポイントと違う場合は "
        "config.json の project_endpoint を直す。"
    )
    print("次は: just grant-role  →  just create-agent")


if __name__ == "__main__":
    main()
