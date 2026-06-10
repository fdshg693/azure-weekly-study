"""② Foundry 組み込みの Web 検索ツール（サーバーサイド実行）だけを与えたエージェント。

FoundryChatClient.get_web_search_tool() が返すのは **ホスト型ツール**。ローカル実装は不要で、
検索は Foundry プロジェクトの Responses API 側（サーバーサイド）で実行される。最新情報を
必要とする質問に対し、モデルが自動的に Web 検索を使って答える。

前提:
  - az login 済み
  - .env か環境変数に FOUNDRY_PROJECT_ENDPOINT / FOUNDRY_MODEL
  - プロジェクト側で Web 検索ツールが利用可能になっていること
"""

import asyncio

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from azure.identity import AzureCliCredential

from _config import get_endpoint, get_model


async def main() -> None:
    agent = Agent(
        client=FoundryChatClient(
            project_endpoint=get_endpoint(),
            model=get_model(),
            credential=AzureCliCredential(),
        ),
        instructions=(
            "あなたはリサーチアシスタント。最新情報が必要なときは Web 検索を使い、"
            "日本語で要点をまとめて答える。"
        ),
        # サーバーサイドで実行されるホスト型ツール。ローカル関数は不要。
        tools=[FoundryChatClient.get_web_search_tool()],
    )

    q = "Microsoft Foundry の最近のアップデートを教えて。"
    result = await agent.run(q)
    print(f"Q: {q}\nA: {result}")


if __name__ == "__main__":
    asyncio.run(main())
