"""検証メール送信ヘルパ。`EMAIL_MODE` で local / acs を切り替える。

- local: 実送信せず、検証リンクをコンソールと `.verify-links/<email>.txt` に出力する
         （メール基盤なしで「リンクを踏んで検証」フローだけを体験するため）。
- acs:   Azure Communication Services (Email) で本物の検証メールを送る。

同一コードを環境変数で切り替える（CLAUDE.md / KNOWLEDGE.md の方針）。
"""
import os
from pathlib import Path

# 既定は local（外部送信なし）。Azure では App Settings で acs にする。
EMAIL_MODE = os.getenv("EMAIL_MODE", "local").strip().lower()

# ローカル出力先：プロジェクト直下の .verify-links/（gitignore 済み）。
# このファイル（functions/email_helper.py）の 1 つ上がプロジェクトルート。
_VERIFY_LINKS_DIR = Path(__file__).resolve().parent.parent / ".verify-links"


def send_verification_email(to_email: str, verify_link: str) -> None:
    """検証リンクをメール（acs）またはファイル/コンソール（local）で届ける。"""
    if EMAIL_MODE == "acs":
        _send_acs(to_email, verify_link)
    else:
        _send_local(to_email, verify_link)


def _send_local(to_email: str, verify_link: str) -> None:
    _VERIFY_LINKS_DIR.mkdir(exist_ok=True)
    # メールアドレスをそのままファイル名に使う（学習用。衝突や記号は気にしない）。
    out = _VERIFY_LINKS_DIR / f"{to_email}.txt"
    out.write_text(verify_link, encoding="utf-8")
    # func のコンソールにも出す（手でコピーして踏めるように）。
    print(f"[EMAIL_MODE=local] {to_email} の検証リンク: {verify_link}")
    print(f"  （{out} にも書き出しました）")


def _send_acs(to_email: str, verify_link: str) -> None:
    # 遅延 import：local モードでは ACS SDK を読み込まない。
    from azure.communication.email import EmailClient

    conn = os.environ["ACS_CONNECTION_STRING"]
    sender = os.environ["ACS_SENDER_ADDRESS"]  # 例: DoNotReply@<id>.azurecomm.net
    client = EmailClient.from_connection_string(conn)

    message = {
        "senderAddress": sender,
        "recipients": {"to": [{"address": to_email}]},
        "content": {
            "subject": "メールアドレスの確認",
            "plainText": (
                "メッセージアプリへのご登録ありがとうございます。\n"
                f"以下のリンクを開いて確認を完了してください:\n{verify_link}\n"
            ),
            "html": (
                "<p>メッセージアプリへのご登録ありがとうございます。</p>"
                f'<p><a href="{verify_link}">こちらをクリックして確認を完了</a></p>'
            ),
        },
    }
    # begin_send は長時間ポーラー。確実に送るため完了まで待つ（学習用の同期送信）。
    poller = client.begin_send(message)
    poller.result()
    print(f"[EMAIL_MODE=acs] {to_email} へ検証メールを送信しました。")
