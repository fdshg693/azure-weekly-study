# az acr build ./api でクラウド側ビルドされる前提。
# このプロジェクトはイメージの作り分けは無く 1 種類のみ (主役は Bicep/az 側の ID 設定)。
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "30", "app:app"]
