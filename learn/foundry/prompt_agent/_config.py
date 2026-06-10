"""config.json の読み書きヘルパ (azure_ml の _client.py に相当)。

コントロールプレーン (00) が作成したリソースの接続情報を 1 ファイルに集約し、
データプレーン (01/02) と後片付け (99) がそれを読む。これで「どのプロジェクトに
繋ぐか」を各スクリプトにハードコードせず一箇所で管理できる。
"""

import json
from pathlib import Path

# .env (このフォルダ直下) があれば環境変数として読み込む。各スクリプトは _config を
# import するので、ここで一度読めば全体に効く。既存の環境変数は上書きしない
# (シェルや justfile で明示した値が .env より優先される = override=False の既定)。
try:
    from dotenv import load_dotenv

    load_dotenv(Path(__file__).with_name(".env"))
except ModuleNotFoundError:
    pass

CONFIG_PATH = Path(__file__).with_name("config.json")


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        raise SystemExit(
            "config.json が見つからない。先に 00_provision.py (just provision) を実行する。"
        )
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def save_config(cfg: dict) -> None:
    CONFIG_PATH.write_text(
        json.dumps(cfg, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(f"wrote {CONFIG_PATH.name}")
