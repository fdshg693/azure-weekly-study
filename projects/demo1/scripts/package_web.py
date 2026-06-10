"""HTMX 静的サイトを Static Web Apps デプロイ用にパッケージング。

`terraform output -raw function_app_url` の値で web/index.html の
__FUNCTION_URL__ プレースホルダを置換し、web-dist/ に出力する。

justfile からは `python scripts/package_web.py` で呼ばれる想定。
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

PLACEHOLDER = "__FUNCTION_URL__"
PROJECT_ROOT = Path(__file__).resolve().parent.parent
SRC_HTML = PROJECT_ROOT / "web" / "index.html"
DIST_DIR = PROJECT_ROOT / "web-dist"


def terraform_output(name: str) -> str:
    result = subprocess.run(
        ["terraform", "output", "-raw", name],
        cwd=PROJECT_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def main() -> int:
    func_url = terraform_output("function_app_url")

    if DIST_DIR.exists():
        shutil.rmtree(DIST_DIR)
    DIST_DIR.mkdir(parents=True)

    html = SRC_HTML.read_text(encoding="utf-8")
    if PLACEHOLDER not in html:
        # 置換対象がない＝テンプレートが意図せず変わった可能性。デプロイ前に気付けるよう失敗させる。
        print(
            f"error: placeholder {PLACEHOLDER!r} not found in {SRC_HTML}",
            file=sys.stderr,
        )
        return 1

    out_path = DIST_DIR / "index.html"
    out_path.write_text(html.replace(PLACEHOLDER, func_url), encoding="utf-8")

    print(f"Built {out_path.relative_to(PROJECT_ROOT)} (FUNCTION_URL={func_url})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
