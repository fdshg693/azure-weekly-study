# `az acr build ./app` でクラウド側ビルドされる前提の最小イメージ。
# サーバーではなく「起動して終了する」ワーカーなので EXPOSE も常駐コマンドも無い。
FROM python:3.12-slim

WORKDIR /app

# 依存は標準ライブラリのみ。requirements は将来の追加用に置いてある（中身は空）。
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY worker.py .

# 1 回実行して終了する。終了コードが Job 実行の成否になる。
CMD ["python", "worker.py"]
