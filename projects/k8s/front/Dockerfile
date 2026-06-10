# az acr build ./front でクラウド側ビルドされる前提。
# 静的ページを配信するだけのフロント。ポート 80 で待ち受ける。
FROM nginx:1.27-alpine

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80
