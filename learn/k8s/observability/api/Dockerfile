# az acr build ./api でクラウド側ビルドされる前提。
# 監視のグラフを動かすための「負荷つまみ付き」の小さな Flask アプリ。
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# 応答に出すバージョン文字列 (どの版が動いているか分かるように)。
ARG APP_VERSION=v1
ENV APP_VERSION=$APP_VERSION

EXPOSE 8080

# /work で CPU を焼く都合上、worker は複数 (プロセス並列で真の並列負荷を作れる)。
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "60", "app:app"]
