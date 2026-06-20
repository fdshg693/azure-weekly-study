# az acr build ./api でクラウド側ビルドされる前提。
# 1 つのソースから ARG を変えて v1 / v2 / v2-bad の複数イメージを作るのがミソ。
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# --- ビルド時に挙動を焼き込む引数 ---
# APP_VERSION : 応答に出すバージョン文字列 (例: v1 / v2 / v2-bad)
# BREAK_HEALTH: true なら /healthz が 500 を返す (壊れた v2 のロールアウト実験用)
ARG APP_VERSION=dev
ARG BREAK_HEALTH=false
ENV APP_VERSION=$APP_VERSION
ENV BREAK_HEALTH=$BREAK_HEALTH

EXPOSE 8080

# probe (/healthz) と業務エンドポイントを 8080 で待ち受ける。
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "30", "app:app"]
