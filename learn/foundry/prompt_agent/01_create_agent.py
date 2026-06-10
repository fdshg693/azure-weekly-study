"""プロンプトエージェントを作成する (データプレーン / クイックスタート本体・前半)。

00 で作った project_endpoint へ AIProjectClient で接続し、PromptAgentDefinition
(モデル + 指示文) を create_version でエージェントとして登録する。プロンプトエージェントは
「モデル + instructions (+ tools)」を宣言的に束ねたもの = 軽量・コード少なめが持ち味。

前提:
  - az login 済み
  - 自分に project スコープの Foundry User (旧 Azure AI User) ロール (= just grant-role)
    これが無いと DefaultAzureCredential での呼び出しが 401/403 になる。
"""

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition
from azure.identity import DefaultAzureCredential

from _config import load_config


def main() -> None:
    cfg = load_config()

    project = AIProjectClient(
        endpoint=cfg["project_endpoint"],
        credential=DefaultAzureCredential(),
    )

    # create_version: 同名で呼ぶたびに version が上がる (定義の更新履歴が残る)
    agent = project.agents.create_version(
        agent_name=cfg["agent_name"],
        definition=PromptAgentDefinition(
            model=cfg["model_name"],  # 00 のデプロイ名と一致している必要がある
            instructions="You are a helpful assistant that answers general questions",
        ),
    )
    print(f"agent created (id={agent.id}, name={agent.name}, version={agent.version})")
    print("次は: just chat")


if __name__ == "__main__":
    main()
