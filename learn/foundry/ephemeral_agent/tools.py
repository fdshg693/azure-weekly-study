"""エージェントに渡す **カスタムツール（ローカル実行）** を定義する。

ここでは「名前を渡すと、その人物の個人情報（すべて架空）を返す」関数を 1 つ用意する。
@tool デコレータを付けると Agent Framework が引数スキーマ（型・説明）を自動生成し、
モデルが「この情報が要る」と判断したタイミングで、この Python 関数を **ローカルで** 呼ぶ
（= function calling）。Web 検索ツールが Foundry 側（サーバーサイド）で動くのと対照的に、
こちらは自分のプロセス内で実行される。

ポイント:
  - approval_mode="never_require" … 呼び出しに人間の承認を挟まず自動実行する
  - Annotated[..., Field(description=...)] … この説明がそのまま LLM 向けの引数ドキュメントになる

※ 返すデータはすべてダミー（実在しない）。実運用では社内ディレクトリや DB を
  引く処理に置き換える想定。
"""

import hashlib
import json
from typing import Annotated

from agent_framework import tool
from pydantic import Field

# あらかじめ用意した架空の社員レコード（実在しない人物・連絡先）。
_FAKE_DIRECTORY: dict[str, dict] = {
    "佐藤 花子": {
        "employee_id": "EMP-1024",
        "department": "クラウド基盤部",
        "title": "シニアエンジニア",
        "email": "hanako.sato@example.co.jp",
        "phone": "080-0000-1024",
        "location": "東京",
    },
    "山田 太郎": {
        "employee_id": "EMP-2048",
        "department": "営業企画部",
        "title": "マネージャー",
        "email": "taro.yamada@example.co.jp",
        "phone": "080-0000-2048",
        "location": "大阪",
    },
}

_DEPARTMENTS = ["クラウド基盤部", "営業企画部", "人事部", "研究開発部", "情報システム部"]
_TITLES = ["メンバー", "リーダー", "マネージャー", "シニアエンジニア", "ディレクター"]
_LOCATIONS = ["東京", "大阪", "名古屋", "福岡", "札幌"]


def _fabricate(name: str) -> dict:
    """ディレクトリに無い名前向けに、名前から決定的にダミー個人情報を生成する。

    hashlib で名前 → 数値に変換し、各リストのインデックスに使う。random を使わないので
    同じ名前なら毎回同じ結果になり、学習・デモで再現性がある。
    """
    h = int(hashlib.md5(name.encode("utf-8")).hexdigest(), 16)
    num = h % 9000 + 1000
    return {
        "employee_id": f"EMP-{num}",
        "department": _DEPARTMENTS[h % len(_DEPARTMENTS)],
        "title": _TITLES[(h // 7) % len(_TITLES)],
        "email": f"user{num}@example.co.jp",
        "phone": f"080-0000-{num:04d}",
        "location": _LOCATIONS[(h // 13) % len(_LOCATIONS)],
    }


@tool(approval_mode="never_require")
def lookup_person(
    name: Annotated[str, Field(description="調べたい人物のフルネーム（例: 佐藤 花子）")],
) -> str:
    """指定した名前の人物の個人情報（所属・役職・連絡先など、すべて架空）を返す。"""
    record = _FAKE_DIRECTORY.get(name) or _fabricate(name)
    # モデルが解釈しやすいよう JSON 文字列で返す。
    return json.dumps({"name": name, **record}, ensure_ascii=False)
