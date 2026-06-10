"""① カスタムツール（ローカル実行）だけを与えたエフェメラルエージェント。

tools=lookup_person を渡すと、モデルは「個人情報が必要だ」と判断したときに
ローカルの lookup_person を自動で呼び、その戻り値を使って自然文で答える。
エージェント定義（instructions / tools / model）は **このコード内にしか存在せず**、
Foundry 側にエージェントリソースは作られない（= エフェメラル）。プロセスが終われば消える。

前提:
  - az login 済み（AzureCliCredential がそのトークンを使う）
  - .env か環境変数に FOUNDRY_PROJECT_ENDPOINT / FOUNDRY_MODEL（.env.example 参照）
"""

import asyncio

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from azure.identity import AzureCliCredential

from _config import get_endpoint, get_model
from tools import lookup_person


async def main() -> None:
    agent = Agent(
        client=FoundryChatClient(
            project_endpoint=get_endpoint(),
            model=get_model(),
            credential=AzureCliCredential(),
        ),
        instructions=(
            "あなたは社員ディレクトリのアシスタント。人物について聞かれたら "
            "lookup_person ツールで情報を取得し、日本語で簡潔に答える。"
        ),
        tools=lookup_person,
    )

    q = "佐藤 花子さんの所属部署と連絡先を教えて。"
    result = await agent.run(q)
    print(f"Q: {q}\nA: {result}")


if __name__ == "__main__":
    asyncio.run(main())
