{{/*
イメージ参照を組み立てるヘルパ。registry/repository:tag の形に統一する。
テンプレートのあちこちで同じ式を書かないための共通化 (Kustomize の images
transformer に対応する「実イメージの差し込み口」を 1 箇所にまとめる)。
*/}}
{{- define "app.apiImage" -}}
{{ .Values.image.registry }}/{{ .Values.image.apiRepository }}:{{ .Values.image.tag }}
{{- end -}}

{{- define "app.frontImage" -}}
{{ .Values.image.registry }}/{{ .Values.image.frontRepository }}:{{ .Values.image.tag }}
{{- end -}}
