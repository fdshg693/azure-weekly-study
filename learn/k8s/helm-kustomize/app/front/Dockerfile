# az acr build ./app/front でクラウド側ビルドされる前提。
# 静的ページを配信し、/api を api Service へプロキシする (default.conf 参照)。
FROM nginx:1.27-alpine

# 既定の server 設定を置き換える (/api プロキシを足すため)。
COPY default.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80
