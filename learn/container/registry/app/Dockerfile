# container/registry の「載せる対象」となる最小 Web イメージ。
# このトピックの主眼は「作る」ではなく「載せる」なので、中身は nginx の静的配信に徹する。
# `az acr build`（ACR Tasks）でクラウド側ビルドする前提（ローカル Docker 不要）。
#
# VERSION を build-arg で受け取り、ページに焼き込む。これにより
# 「同じタグ・違う中身」を作り分けられ、tag vs digest（内容ハッシュ）の実験に使える。
#   例: az acr build --build-arg VERSION=v1-edited --image web:v1 ./app
FROM nginx:alpine

ARG VERSION=v1

COPY index.html /usr/share/nginx/html/index.html

# プレースホルダ __VERSION__ を build-arg の値に置換して焼き込む。
RUN sed -i "s/__VERSION__/${VERSION}/g" /usr/share/nginx/html/index.html

EXPOSE 80
