# MERMAID — `aci` の構成と実験

## 構成図（registry の出力を参照して keyless pull）

```mermaid
graph TD
    subgraph REGRG["RG rg-container-registry (Step 1)"]
        ACR["ACR acrreg...<br/>repository web : tag v1"]
        UAMI["消費者 UAMI uami-reg-pull"]
        ROLE["AcrPull (scope=ACR)"]
        ROLE -. 付与 .- UAMI
    end

    subgraph ACIRG["RG rg-container-aci (このプロジェクト)"]
        CG["Container Group cg-aci-web<br/>(Public IP + FQDN)<br/>container: web (nginx)"]
    end

    Dev["手元の端末 (az / Task)"]
    User["ブラウザ / curl"]

    Dev -- "deploy (registry の出力を注入)" --> CG
    UAMI == "assign + imageRegistryCredentials.identity" ==> CG
    CG -- "keyless pull web:v1 (AcrPull 経由)" --> ACR
    User -- "HTTP http://aci-xxxx.region.azurecontainer.io" --> CG
```

## 実験1: restartPolicy で再起動の有無が変わる（`task restart-demo`）

```mermaid
flowchart TD
    Start["コンテナが終了 (exitCode)"] --> Q{restartPolicy?}
    Q -- Always --> R1["毎回再起動<br/>restartCount が増え続ける"]
    Q -- OnFailure --> Q2{exitCode != 0?}
    Q2 -- "はい (異常)" --> R2["再起動する"]
    Q2 -- "いいえ (正常 0)" --> R3["再起動しない → Terminated"]
    Q -- Never --> R4["再起動しない → Terminated"]
```

## 実験2: AcrPull を外すと keyless pull が 403（`task acrpull-off → recreate → show`）

UAMI 本人を主語にした 403 体感。Step 1 では SP で代役した宿題をここで回収する。

```mermaid
sequenceDiagram
    participant Dev as 手元 (az / Task)
    participant ACR as ACR
    participant ACI as Container Group (UAMI で pull)

    Note over Dev,ACR: acrpull-off … 消費者 UAMI の AcrPull を剥奪
    Dev->>ACI: recreate (削除→作成)
    ACI->>ACR: 起動時に pull (UAMI=認証OK / AcrPull 無し=認可NG)
    ACR--xACI: 403 "Failed to pull image"
    Note over ACI: events に pull 失敗が出る (task show)

    Note over Dev,ACR: acrpull-on … AcrPull を付与し直す
    Dev->>ACI: recreate
    ACI->>ACR: pull (認証OK + 認可OK)
    ACR-->>ACI: Pulled → Started
    Note over ACI: task probe でページが返る＝復活
```

> 認証（UAMI という誰か）は変えず・**認可（AcrPull の有無）だけ**で可否が変わる＝認証と認可は別物。

## 実験3: コンテナグループ（同居）は localhost を共有（`task sidecar`）

```mermaid
graph LR
    subgraph CG["Container Group cg-aci-sidecar (同じ localhost / ライフサイクル)"]
        WEB["web (nginx) :80<br/>グループの公開ポート"]
        SIDE["sidecar<br/>公開ポート無し"]
        SIDE -- "wget http://localhost:80" --> WEB
    end
    User["外部"] -- "HTTP :80" --> WEB
```

> sidecar は外に出ず localhost で隣の web に届く＝同居コンテナは network namespace を共有する（Pod 内マルチコンテナの最小形）。
