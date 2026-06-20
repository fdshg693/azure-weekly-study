# helm-kustomize — マニフェストのテンプレート化と環境差分が主役

k8s 学習プラン（[../PLAN.md](../PLAN.md)）の **Step 3**。
`simple` で作った AKS / ACR を**そのまま流用**し（新しい Bicep は無い）、同じベースのマニフェストを
**Kustomize の overlay** と **Helm の values** という 2 つの方法で `dev` / `prod` に出し分ける。
狙いは次の 2 点。

1. **テンプレート化**: これまでの `__ACR_LOGIN_SERVER__` 文字列置換（sed）を卒業し、
   Kustomize の **images transformer** / Helm の **`--set` + values** で「実イメージを構造的に差し込む」。
2. **環境差分**: 1 つのベースから**差分だけ**で dev / prod を作り、レプリカ数・リソース・HPA・設定・host が
   変わることを `kubectl kustomize` / `helm template` で**レンダリング差分**として可視化する。

> `simple`/`config-rollout` までと違い、このプロジェクトは **DB を使わない**。テンプレート化と環境差分に
> 集中するための割り切り（後述）。アプリは `version` / `env` / `message` / `pod` を返すだけ。

## 前提

- `simple` 側のインフラが**デプロイ済み**であること（`learn/k8s/simple` で `just group-create` → `just deploy-local`）。
  - 既定のリソースグループ `rg-aks-demo` / デプロイ名 `main` の出力（ACR 名・ACR ログインサーバ）をこのプロジェクトが読む。
- `az login` 済み、`kubectl` あり（無ければ `simple` の `just install-kubectl`）。
- **`kustomize` CLI** と **`helm` CLI** が必要（この章の主役）。`just check-tools` で確認。無ければ:
  - kustomize: `winget install Kubernetes.kustomize`（または `az aks install-cli` 同梱の `kubectl` でも `kubectl kustomize`/`apply -k` は使えるが、`kustomize edit` は standalone が必要）
  - helm: `winget install Helm.Helm`
- **simple / config-rollout のアプリ層は止めておく**ことを推奨。本プロジェクトの Ingress は host ベース
  （`hk-dev.local` / `hk-prod.local`）で衝突を避けているが、ブラウザ観察は **`just pf`（port-forward）** を使うので
  Ingress 競合を気にせず dev / prod を別ポートに並べて見られる。

## 構成

```
helm-kustomize/
├─ app/                         # dev/prod 共有の最小アプリ (イメージは 1 種類だけ)
│  ├─ api/                     # version/env/message/pod を返す Flask API
│  └─ front/                   # /api をプロキシする nginx (port-forward だけで完結)
├─ kustomize/
│  ├─ base/                    # 全環境共通の素のマニフェスト (image は記号名 app-api/app-front)
│  │  ├─ kustomization.yaml
│  │  ├─ configmap.yaml / api-deployment.yaml / front-deployment.yaml / services.yaml / ingress.yaml
│  └─ overlays/
│     ├─ dev/                  # 差分: namespace=hk-dev, 設定, host (台数/リソースは base のまま=最小)
│     └─ prod/                 # 差分: namespace=hk-prod, replicas=3, リソース増, HPA 追加, 設定, host
├─ helm/app/                    # 上と同じものを Helm chart で表現
│  ├─ Chart.yaml
│  ├─ values.yaml              # ベース (= Kustomize の base 相当)
│  ├─ values-dev.yaml / values-prod.yaml   # 環境差分 (= overlay 相当)
│  └─ templates/               # configmap/api/front/services/ingress/hpa + _helpers.tpl
├─ scripts/                     # 複雑な処理は justfile に埋めず PowerShell に分離
│  ├─ lib.ps1                  # simple のデプロイ出力 (ACR) を取得
│  ├─ credentials.ps1 / acr-build.ps1
│  ├─ kz-deploy.ps1            # ACR を kustomize edit で注入 → apply/diff → placeholder へ戻す
│  ├─ hl-deploy.ps1            # helm upgrade --install (--set image.registry で ACR 注入)
│  └─ render-diff.ps1          # dev vs prod のレンダリング差分を表示
└─ justfile                     # 上記を呼ぶ薄い入口
```

## 準備（共通）

```pwsh
just check-tools                # kustomize / helm が入っているか確認
just credentials                # simple の AKS の接続情報を取り込む
just acr-build                  # hk/api:v1 / hk/front:v1 を simple の ACR にビルド
```

---

## ルート A — Kustomize で出し分ける

### A-1. まず「レンダリング差分」を見る（クラスタに触れない）

```pwsh
just kz-render dev              # dev のマニフェストを生成して目で見る
just kz-render prod             # prod も
just kz-render-diff             # dev と prod の生成結果の差分を並べて表示 ★この章の主目的
```

学び: `kz-render-diff` の差分が **replicas（1↔3）/ resources / HPA の有無 / APP_ENV・APP_MESSAGE / Ingress host /
namespace** だけに出る。**同じ base から overlay の差分だけで 2 環境ができる**ことが一目で分かる。

### A-2. デプロイして実機で確認

```pwsh
just kz-up dev                  # 実 ACR を kustomize edit set image で注入してから apply
just kz-up prod
just status dev                 # hk-dev の Pod/Svc/Ingress/HPA/ConfigMap
just status prod                # hk-prod は api が 3 Pod、HPA あり
```

`kz-up` は `__ACR_LOGIN_SERVER__` の sed の代わりに、`kustomize edit set image` で images transformer の
`newName/newTag` を実 ACR に書き換えてから `kubectl apply -k` する。**直後に placeholder へ戻す**ので作業ツリーは汚れない。

### A-3. ブラウザで dev と prod を見比べる

```pwsh
# 別々のターミナルで
just pf dev 8081                # → http://localhost:8081
just pf prod 8082               # → http://localhost:8082
```

「1 秒ごとに自動更新」をオンにすると、dev は env=dev のバッジ・常に同じ pod、prod は env=prod・**3 つの pod 名が
入れ替わる**のが見える（front の nginx が `/api` を api Service にプロキシするので port-forward だけで完結）。

### A-4. 「変更 → 差分 → 適用」の往復（因果）

```pwsh
# 例: prod のレプリカを 3→5 に変えてみる
#   kustomize/overlays/prod/kustomization.yaml の replicas count を 5 に編集 → 保存
just kz-diff prod               # クラスタ実体と overlay の差分 (apply 前の影響確認)
just kz-up prod                 # 適用 → just status prod で 5 Pod になるのを確認
```

`kz-diff` は `kubectl diff -k` で**今のクラスタと overlay の差**だけを見せる。GitOps 的な「宣言 → 差分 → 適用」を体感する。

---

## ルート B — Helm で出し分ける（同じことを別ツールで）

### B-1. レンダリング差分

```pwsh
just hl-render dev              # values.yaml + values-dev.yaml を当てた結果
just hl-render prod
just hl-render-diff             # dev と prod の生成結果の差分 ★Kustomize と同じ観察
```

学び: Kustomize が **patch/transformer（マージと変換）** でベースを書き換えるのに対し、Helm は
**テンプレート言語 + values（穴埋め）** で生成する。出力（差分の中身）はほぼ同じになる ＝ **同じ問題を別アプローチで解く**。

### B-2. デプロイ

```pwsh
just hl-up dev                  # helm upgrade --install app-dev ... --set image.registry=<ACR>
just hl-up prod                 # release=app-prod, namespace=hk-prod, HPA 有効
just hl-status prod             # リリース状態 + 適用済み values (helm get values)
```

ACR は **`--set image.registry=<ACR>`** で実行時に注入（ファイルは書き換えない）。これが Kustomize の
images transformer に対応する Helm のやり方。

### B-3. ブラウザ確認は A-3 と同じ（`just pf dev/prod`）。

> ⚠️ Kustomize 版（`kz-up`）と Helm 版（`hl-up`）は**同じ namespace (`hk-dev`/`hk-prod`) に同名リソース**を作る。
> 混在させると所有権が衝突するので、**どちらか一方を試したら `just kz-down`/`just hl-down` で消してから**もう一方を試す。

## 2 ツールの比較（この章のまとめ）

| 観点 | Kustomize | Helm |
|---|---|---|
| 仕組み | base + overlay の**マージ/変換**（テンプレート言語なし） | **Go テンプレート + values** で生成 |
| 実イメージ注入 | images transformer（`kustomize edit set image`） | `--set image.registry` / values |
| 環境差分 | overlay（patch・replicas・images・namespace transformer） | values-dev / values-prod |
| 条件分岐（例: prod だけ HPA） | overlay の `resources` に hpa.yaml を**足す** | `{{- if .Values.hpa.enabled }}` |
| リリース管理 | 無し（`kubectl apply -k` するだけ） | **あり**（`helm list` / `status` / `rollback` / 履歴） |
| ツール | kubectl 内蔵（`apply -k`）＋ edit に standalone | 専用 CLI `helm` |

## 後片付け

```pwsh
just kz-down dev ; just kz-down prod      # Kustomize で作ったものを消す
just hl-down dev ; just hl-down prod      # Helm で作ったものを消す
just destroy                              # hk-dev / hk-prod namespace ごと一括削除
```

`simple` のインフラ（AKS/ACR）まで消したい場合は `learn/k8s/simple` 側で `just destroy`。

## 設計上の割り切り

- インフラは `simple` を流用し、新規 Bicep は持たない（PLAN の「既存 AKS をそのまま使う」方針）。
- **DB を持たない**。テンプレート化・環境差分が主役で、Secret/DB は前章までで扱ったため意図的に外した。
- 環境差分はイメージでは出さない（`hk/api:v1` 1 種類のみ）。違いを「設定・台数・リソース・HPA」に寄せ、
  「**同じ成果物を環境ごとに構成し分ける**」というテンプレート化の本質に集中する。
- `kz-up` は ACR を注入したら直後に placeholder へ戻す。リポジトリに実レジストリ名を残さないための割り切り
  （`kustomize edit` を CI で回す典型運用の縮小版）。
