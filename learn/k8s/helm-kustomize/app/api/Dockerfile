# az acr build ./app/api でクラウド側ビルドされる前提。
# このプロジェクトでは 1 種類のイメージ (hk/api:v1) だけ作り、
# 環境差分はイメージではなく Kustomize/Helm 側 (設定・台数) で出すのが狙い。
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# 応答に出すバージョン文字列 (イメージに焼き込む不変の情報)。
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION

EXPOSE 8080

# probe (/healthz) と業務エンドポイント (/api) を 8080 で待ち受ける。
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "30", "app:app"]
