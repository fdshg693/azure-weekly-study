"""作成したエージェントと会話する (データプレーン / クイックスタート本体・後半)。

OpenAI 互換クライアント (project.get_openai_client) で conversation を 1 本作り、
agent_reference でエージェントを指定して 2 ターン投げる。同じ conversation を使い回すと
会話履歴が維持され、2 ターン目の "And what is the capital city?" が 1 ターン目の文脈
(France) を引き継いで「Paris」と答える ― ここがプロンプトエージェントの肝。
"""

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

from _config import load_config


def main() -> None:
    cfg = load_config()

    project = AIProjectClient(
        endpoint=cfg["project_endpoint"],
        credential=DefaultAzureCredential(),
    )
    openai = project.get_openai_client()

    # 複数ターンを束ねる入れ物。これを使い回すことで履歴が連鎖する。
    conversation = openai.conversations.create()
    agent_ref = {"name": cfg["agent_name"], "type": "agent_reference"}

    q1 = "What is the size of France in square miles?"
    r1 = openai.responses.create(
        conversation=conversation.id,
        extra_body={"agent_reference": agent_ref},
        input=q1,
    )
    print(f"Q1: {q1}\nA1: {r1.output_text}\n")

    # 同じ conversation.id を渡すので、France の文脈を引き継ぐ
    q2 = "And what is the capital city?"
    r2 = openai.responses.create(
        conversation=conversation.id,
        extra_body={"agent_reference": agent_ref},
        input=q2,
    )
    print(f"Q2: {q2}\nA2: {r2.output_text}")


if __name__ == "__main__":
    main()
