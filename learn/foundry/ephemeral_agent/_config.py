"""エフェメラルエージェントの接続設定を .env / 環境変数から読む。

このプロジェクトは **リソースを作らない**（作成手順は prompt_agent と同じなので省略）。
必要なのは次の 2 つだけで、両方を .env か環境変数から「注入」する:
  - FOUNDRY_PROJECT_ENDPOINT … どの Foundry プロジェクトに繋ぐか
  - FOUNDRY_MODEL            … どのデプロイ済みモデルを使うか

prompt_agent を先に動かしているなら、そこで生成された config.json の project_endpoint と
model_name をそのまま流用できる（.env にコピーするだけ）。
"""

import os
from pathlib import Path

# .env (このフォルダ直下) があれば環境変数として読み込む。各スクリプトは _config を
# import するので、ここで一度読めば全体に効く。既存の環境変数は上書きしない
# (シェルや justfile で明示した値が .env より優先される = override=False の既定)。
try:
    from dotenv import load_dotenv

    load_dotenv(Path(__file__).with_name(".env"))
except ModuleNotFoundError:
    pass


def get_endpoint() -> str:
    """Foundry プロジェクトのエンドポイント（必須）。"""
    ep = os.environ.get("FOUNDRY_PROJECT_ENDPOINT")
    if not ep:
        raise SystemExit(
            "FOUNDRY_PROJECT_ENDPOINT が未設定。.env か環境変数で指定する"
            "（.env.example 参照。prompt_agent/config.json の project_endpoint を流用可）。"
        )
    return ep


def get_model() -> str:
    """使用するモデルのデプロイ名（既定: gpt-4.1-mini）。"""
    return os.environ.get("FOUNDRY_MODEL", "gpt-4.1-mini")
