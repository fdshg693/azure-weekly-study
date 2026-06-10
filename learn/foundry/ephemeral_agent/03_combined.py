"""③ Web 検索（サーバーサイド）＋ カスタムツール（ローカル）を両方与えたエージェント。

このプロジェクトの本題。1 つのエージェントに 2 種類のツールを渡し、質問に応じて
モデルがどちらを（あるいは両方を）使い分けるかを確認する。
  - lookup_person          … ローカルで実行される個人情報取得（架空）
  - get_web_search_tool()  … Foundry 側（サーバーサイド）で実行される Web 検索

下の質問は「人物の所属を調べる（= ローカルツール）」と「その分野の最新ニュースを探す
（= Web 検索）」の両方を要求するため、2 ツールの連携を 1 回の実行で観察できる。

前提:
  - az login 済み
  - .env か環境変数に FOUNDRY_PROJECT_ENDPOINT / FOUNDRY_MODEL
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
            "あなたは有能なアシスタント。社員情報が必要なら lookup_person を、"
            "最新の外部情報が必要なら Web 検索を使う。両方必要なら両方使ってよい。"
            "最後に日本語でまとめて答える。"
        ),
        tools=[
            lookup_person,                            # ローカル実行のカスタムツール
            FoundryChatClient.get_web_search_tool(),  # サーバーサイドの Web 検索
        ],
    )

    q = (
        "佐藤 花子さんの所属部署を調べて、その部署のテーマに関連する "
        "最新の技術ニュースを Web 検索で 2 件教えて。"
    )
    result = await agent.run(q)
    print(f"Q: {q}\nA: {result}")


if __name__ == "__main__":
    asyncio.run(main())
